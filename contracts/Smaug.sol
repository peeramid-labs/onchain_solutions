// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.28;
import {BaseGuard} from "@safe-global/safe-contracts/contracts/base/GuardManager.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
struct ScheduledUpdateTTL {
    uint256 createdAt;
    uint256 newValue;
}

struct Policy {
    uint256 inDay;
    uint256 inBlock;
    uint256 inTX;
    uint256 inTotal;
}

struct ScheduledUpdate {
    uint256 createdAt;
    Policy newPolicy;
}

struct BudgetTracker {
    mapping(uint256 dayNumber => uint256 volume) dailyValue;
    mapping(uint256 blockNumber => uint256 volume) blockValue;
    mapping(bytes32 txHash => uint256 volume) txValue;
    uint256 totalValue;
}

struct PreApprovedTx {
    bytes32 txHash;
    uint256 timestamp;
}

struct AssetGuard {
    Policy rates;
    BudgetTracker budgetTracker;
    uint256 balanceBeforeExecution;
    bool updateScheduled;
}

struct ContractStorage {
    address safe;
    uint256 ttl;
    ScheduledUpdateTTL scheduledUpdateTTL;
    EnumerableSet.AddressSet assetsList;
    mapping(address asset => AssetGuard) assetProtection;
    mapping(address asset => ScheduledUpdate) scheduledUpdates;
    mapping(bytes32 txHash => PreApprovedTx preApprovedTx) preApprovedTxs;
}

interface ITreasuryGuard {
    /**
     * @notice Schedule a TTL update
     * @param _ttl The new TTL
     */
    function scheduleTTLUpdate(uint256 _ttl) external;

    /**
     * @notice Schedule a budget update
     * @param asset The asset to update the budget for
     * @param newPolicy The new policy
     */
    function scheduleBudgetUpdate(
        address asset,
        Policy memory newPolicy
    ) external;

    /**
     * @notice Pre-approve a transaction
     * @param txHash The hash of the transaction
     */
    function preApproveTx(bytes32 txHash) external;

    event TTLSet(uint256 oldTTL, uint256 newTTL);
    event AssetProtectionUpdated(
        address indexed token,
        uint256 inDay,
        uint256 inBlock,
        uint256 inTX,
        uint256 inTotal
    );
    event ScheduledUpdateTTLSet(
        uint256 indexed timestamp,
        uint256 indexed newTTL,
        uint256 indexed ETA
    );
    event ScheduledUpdateAssetProtection(
        address indexed asset,
        uint256 indexed ETA,
        uint256 inDay,
        uint256 inBlock,
        uint256 inTX,
        uint256 inTotal
    );
    event TxApproved(bytes32 txHash, uint256 timestamp);
}

/**
 * @title Smaug
 * @author Peeramid labs
 * @notice Smaug is a guard contract that protects the Safe from being drained by malicious contracts.
 * Smaug (/smaʊɡ/) is a dragon and the main antagonist in J. R. R. Tolkien's 1937 novel The Hobbit, his treasure and the mountain he lives in being the goal of the quest.
 * @custom:security-contact sirt@peeramid.xyz
 */
contract Smaug is
    ITreasuryGuard,
    BaseGuard,
    OwnableUpgradeable,
    EIP712Upgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    bytes32 public constant STORAGE_SLOT =
        keccak256("com.timeismoney.guard.storage");

    function getStorage() internal pure returns (ContractStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    function preApproveTx(bytes32 txHash) external onlyOwner {
        ContractStorage storage s = getStorage();
        s.preApprovedTxs[txHash] = PreApprovedTx({
            txHash: txHash,
            timestamp: block.timestamp
        });
        emit TxApproved(txHash, block.timestamp);
    }

    function scheduleBudgetUpdate(
        address asset,
        Policy memory newPolicy
    ) external onlyOwner {
        ContractStorage storage s = getStorage();
        s.scheduledUpdates[asset] = ScheduledUpdate({
            createdAt: block.timestamp,
            newPolicy: newPolicy
        });
        s.assetProtection[asset].updateScheduled = true;
        emit ScheduledUpdateAssetProtection(
            asset,
            block.timestamp + s.ttl,
            newPolicy.inDay,
            newPolicy.inBlock,
            newPolicy.inTX,
            newPolicy.inTotal
        );
    }

    function setTTL(uint256 _ttl) external onlyOwner {
        ContractStorage storage s = getStorage();
        emit TTLSet(s.ttl, _ttl);
        s.ttl = _ttl;
    }

    function initialize(
        address _owner,
        uint256 _ttl,
        address safe
    ) public initializer {
        __Ownable_init(_owner);
        ContractStorage storage s = getStorage();
        s.ttl = _ttl;
        s.safe = safe;
    }

    function scheduleTTLUpdate(uint256 _ttl) external onlyOwner {
        ContractStorage storage s = getStorage();
        require(
            s.scheduledUpdateTTL.createdAt == 0,
            "TTL update already scheduled"
        );
        require(_ttl > 0, "TTL must be greater than 0");
        s.scheduledUpdateTTL = ScheduledUpdateTTL({
            createdAt: block.timestamp,
            newValue: _ttl
        });

        emit ScheduledUpdateTTLSet(
            block.timestamp,
            _ttl,
            block.timestamp + _ttl
        );
    }

    function dayFromTimestamp(
        uint256 timestamp
    ) internal pure returns (uint256) {
        return timestamp / 1 days;
    }

    error DelegatecallNotAllowed();
    error NotMySafe();
    error DailyBudgetExceeded(uint256 attemptedSpent, uint256 allowedRate);
    error BlockBudgetExceeded(uint256 attemptedSpent, uint256 allowedRate);
    error TxBudgetExceeded(uint256 attemptedSpent, uint256 allowedRate);
    error TotalBudgetExceeded(uint256 attemptedSpent, uint256 allowedRate);

    function dailyCheck(
        AssetGuard storage assetGuard,
        uint256 balanceAfter,
        uint256 balanceBefore,
        uint256 dayNumber
    ) private {
        if (balanceAfter < balanceBefore) {
            uint256 diff = balanceBefore - balanceAfter;
            assetGuard.budgetTracker.dailyValue[dayNumber] += diff;
            require(
                assetGuard.budgetTracker.dailyValue[dayNumber] <=
                    assetGuard.rates.inDay,
                DailyBudgetExceeded(
                    assetGuard.budgetTracker.dailyValue[dayNumber],
                    assetGuard.rates.inDay
                )
            );
        }
    }

    function blockCheck(
        AssetGuard storage assetGuard,
        uint256 balanceAfter,
        uint256 balanceBefore
    ) private {
        if (balanceAfter < balanceBefore) {
            uint256 diff = balanceBefore - balanceAfter;
            assetGuard.budgetTracker.blockValue[block.number] += diff;
            require(
                assetGuard.budgetTracker.blockValue[block.number] <=
                    assetGuard.rates.inBlock,
                BlockBudgetExceeded(
                    assetGuard.budgetTracker.blockValue[block.number],
                    assetGuard.rates.inBlock
                )
            );
        }
    }

    function txCheck(
        AssetGuard storage assetGuard,
        uint256 balanceAfter,
        uint256 balanceBefore,
        bytes32 txHash
    ) private {
        if (balanceAfter < balanceBefore) {
            uint256 diff = balanceBefore - balanceAfter;
            assetGuard.budgetTracker.txValue[txHash] += diff;
            require(
                assetGuard.budgetTracker.txValue[txHash] <=
                    assetGuard.rates.inTX,
                TxBudgetExceeded(
                    assetGuard.budgetTracker.txValue[txHash],
                    assetGuard.rates.inTX
                )
            );
        }
    }

    function totalCheck(
        AssetGuard storage assetGuard,
        uint256 balanceAfter,
        uint256 balanceBefore
    ) private {
        if (balanceAfter < balanceBefore) {
            uint256 diff = balanceBefore - balanceAfter;
            assetGuard.budgetTracker.totalValue += diff;
            require(
                assetGuard.budgetTracker.totalValue <= assetGuard.rates.inTotal,
                TotalBudgetExceeded(
                    assetGuard.budgetTracker.totalValue,
                    assetGuard.rates.inTotal
                )
            );
        }
    }

    function checkAsset(
        address asset,
        AssetGuard storage assetGuard,
        bytes32 txHash
    ) private {
        uint256 balanceAfter = asset == address(0)
            ? msg.sender.balance
            : IERC20(asset).balanceOf(msg.sender);
        uint256 balanceBefore = assetGuard.balanceBeforeExecution;
        uint256 dayNumber = dayFromTimestamp(block.timestamp);
        dailyCheck(assetGuard, balanceAfter, balanceBefore, dayNumber);
        blockCheck(assetGuard, balanceAfter, balanceBefore);
        txCheck(assetGuard, balanceAfter, balanceBefore, txHash);
        totalCheck(assetGuard, balanceAfter, balanceBefore);
    }

    function performUpdates(
        address asset,
        AssetGuard storage assetGuard,
        ContractStorage storage s
    ) private {
        if (assetGuard.updateScheduled) {
            ScheduledUpdate memory update = s.scheduledUpdates[asset];
            if (block.timestamp >= update.createdAt) {
                assetGuard.rates = update.newPolicy;
                assetGuard.updateScheduled = false;
                update.createdAt = 0;
                update.newPolicy = Policy(0, 0, 0, 0);
            }
        }
    }

    function updateTTL(ContractStorage storage s) private {
        if (s.scheduledUpdateTTL.createdAt != 0) {
            if (block.timestamp - s.scheduledUpdateTTL.createdAt > s.ttl) {
                s.ttl = s.scheduledUpdateTTL.newValue;
                s.scheduledUpdateTTL.createdAt = 0;
                s.scheduledUpdateTTL.newValue = 0;
            }
        }
    }

    function runAssetProtection(
        ContractStorage storage s,
        bytes32 txHash
    ) private {
        address[] memory assets = s.assetsList.values();
        updateTTL(s);
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            AssetGuard storage assetGuard = s.assetProtection[asset];
            performUpdates(asset, assetGuard, s);
            checkAsset(asset, assetGuard, txHash);
        }
    }

    function updateBalancesBeforeExecution(ContractStorage storage s) private {
        address[] memory assets = s.assetsList.values();
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            AssetGuard storage assetGuard = s.assetProtection[asset];
            assetGuard.balanceBeforeExecution = asset == address(0)
                ? msg.sender.balance
                : IERC20(asset).balanceOf(msg.sender);
        }
    }

    function checkTransaction(
        address /*to*/,
        uint256 /*value*/,
        bytes memory /*data*/,
        Enum.Operation operation,
        uint256 /*safeTxGas*/,
        uint256 /*baseGas*/,
        uint256 /*gasPrice*/,
        address /*gasToken*/,
        address payable /*refundReceiver*/,
        bytes memory /*signatures*/,
        address /*msgSender*/
    ) external {
        // Safe contracts call guards at soft implementation code, not on proxy level
        // Therefore sufficient level of protection is only available by disallowing delegatecall
        if (operation == Enum.Operation.DelegateCall) {
            revert DelegatecallNotAllowed();
        }

        ContractStorage storage s = getStorage();
        require(msg.sender == s.safe, NotMySafe());
        updateBalancesBeforeExecution(s);
    }

    function checkAfterExecution(bytes32 txHash, bool) external {
        ContractStorage storage s = getStorage();
        require(msg.sender == s.safe, NotMySafe());
        if (
            s.preApprovedTxs[txHash].timestamp == 0 ||
            block.timestamp - s.preApprovedTxs[txHash].timestamp > s.ttl
        ) {
            runAssetProtection(s, txHash);
        }
    }

    function addProtectedAsset(
        address asset,
        Policy memory policy
    ) external onlyOwner {
        ContractStorage storage s = getStorage();
        require(s.assetsList.add(asset), "Already protected");
        s.assetProtection[asset].rates = policy;
    }
}
