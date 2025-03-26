// SPDX-License-Identifier: Business Source License (BSL 1.1)

pragma solidity ^0.8.28;
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
    uint256 createdAt;
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

/**
 * @title Smaug
 * @author Peeramid labs
 * @notice Smaug is a guard contract that protects the Safe from being drained by malicious contracts.
 * Smaug (/smaʊɡ/) is a dragon and the main antagonist in J. R. R. Tolkien's 1937 novel The Hobbit, his treasure and the mountain he lives in being the goal of the quest.
 * @custom:security-contact sirt@peeramid.xyz
 */
contract Smaug is OwnableUpgradeable, EIP712Upgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    bytes32 public constant STORAGE_SLOT =
        keccak256("com.timeismoney.guard.storage");

    function getStorage() internal pure returns (ContractStorage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

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
    event TxApproved(bytes32 indexed txHash, uint256 indexed createdAt);

    function preApproveTx(bytes32 txHash) external onlyOwner {
        ContractStorage storage s = getStorage();
        s.preApprovedTxs[txHash] = PreApprovedTx({
            txHash: txHash,
            createdAt: block.timestamp
        });
        emit TxApproved(txHash, block.timestamp);
    }

    /**
     * @notice Schedule a policy update on a protected asset
     * @param asset The asset to update the policy for
     * @param newPolicy The new policy
     */
    function schedulePolicyUpdate(
        address asset,
        Policy memory newPolicy
    ) external onlyOwner {
        validatePolicy(newPolicy);
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

    function validatePolicy(Policy memory policy) private pure {
        require(policy.inTX > 0, "inTX must be greater than 0");
        require(
            policy.inBlock >= policy.inTX,
            "inBlock must be greater or equal to inTX"
        );
        require(
            policy.inDay >= policy.inBlock,
            "inDay must be greater or equal to inBlock"
        );
        require(
            policy.inTotal >= policy.inDay,
            "inTotal must be greater or equal to inDay"
        );
    }

    /**
     * @notice Initialize the contract
     * @param _owner The owner of the contract
     * @param _ttl The TTL for the contract
     * @param safe The Safe contract address
     * @param assets The assets to protect
     * @param policies The policies for the assets
     */
    function initialize(
        address _owner,
        uint256 _ttl,
        address safe,
        address[] memory assets,
        Policy[] memory policies
    ) public initializer {
        __Ownable_init(_owner);
        ContractStorage storage s = getStorage();
        s.ttl = _ttl;
        s.safe = safe;
        require(_ttl > 0, "TTL must be greater than 0");
        for (uint256 i = 0; i < assets.length; i++) {
            validatePolicy(policies[i]);
            s.assetProtection[assets[i]].rates = policies[i];
            s.assetsList.add(assets[i]);
        }
    }

    /**
     * @notice Schedule a TTL update
     * @param _ttl The new TTL
     */
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

    /**
     * @notice Get the day number from a timestamp
     * @param timestamp The timestamp
     * @return The day number
     */
    function dayFromTimestamp(
        uint256 timestamp
    ) internal pure returns (uint256) {
        return timestamp / 1 days;
    }

    error DelegatecallNotAllowed();
    error NotMySafe();
    error DailyBudgetExceeded(uint256 attemptedSpent, uint256 allowedRate);
    error BlockBudgetExceeded(uint256 attemptedSpent, uint256 allowedRate);
    error TxBudgetExceeded(
        uint256 attemptedSpent,
        uint256 allowedRate,
        bytes32 txHash
    );
    error TotalBudgetExceeded(uint256 attemptedSpent, uint256 allowedRate);

    /**
     * @notice Check the daily budget
     * @param assetGuard The asset guard
     * @param balanceAfter The balance after the transaction
     * @param balanceBefore The balance before the transaction
     * @param dayNumber The day number
     */
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

    /**
     * @notice Check the block budget
     * @param assetGuard The asset guard
     * @param balanceAfter The balance after the transaction
     * @param balanceBefore The balance before the transaction
     */
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

    /**
     * @notice Check the transaction budget
     * @param assetGuard The asset guard
     * @param balanceAfter The balance after the transaction
     * @param balanceBefore The balance before the transaction
     * @param txHash The transaction hash
     */
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
                    assetGuard.rates.inTX,
                    txHash
                )
            );
        }
    }

    /**
     * @notice Check the total budget
     * @param assetGuard The asset guard
     * @param balanceAfter The balance after the transaction
     * @param balanceBefore The balance before the transaction
     */
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

    /**
     * @notice Check the asset
     * @param asset The asset
     * @param assetGuard The asset guard
     * @param txHash The transaction hash
     */
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

    /**
     * @notice Perform the updates
     * @param asset The asset
     * @param assetGuard The asset guard
     * @param s The contract storage
     */
    function performUpdates(
        address asset,
        AssetGuard storage assetGuard,
        ContractStorage storage s
    ) private {
        if (assetGuard.updateScheduled) {
            ScheduledUpdate memory update = s.scheduledUpdates[asset];
            if (block.timestamp - update.createdAt > s.ttl) {
                assetGuard.rates = update.newPolicy;
                assetGuard.updateScheduled = false;
                update.createdAt = 0;
                update.newPolicy = Policy(0, 0, 0, 0);
            }
        }
    }

    /**
     * @notice Update the TTL
     * @param s The contract storage
     */
    function updateTTL(ContractStorage storage s) private {
        if (s.scheduledUpdateTTL.createdAt != 0) {
            if (block.timestamp - s.scheduledUpdateTTL.createdAt > s.ttl) {
                s.ttl = s.scheduledUpdateTTL.newValue;
                s.scheduledUpdateTTL.createdAt = 0;
                s.scheduledUpdateTTL.newValue = 0;
            }
        }
    }

    /**
     * @notice Run the asset protection
     * @param s The contract storage
     * @param txHash The transaction hash
     */
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

    /**
     * @notice Update the balances before execution
     * @param s The contract storage
     */
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

    // Gnosis Safe Guardian Interface specified at
    // https://docs.safe.global/advanced/smart-account-guards/smart-account-guard-tutorial
    function checkTransaction(
        address /*to*/,
        uint256 /*value*/,
        bytes memory /*data*/,
        uint8 operation,
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
        if (operation == 1) {
            revert DelegatecallNotAllowed();
        }

        ContractStorage storage s = getStorage();
        require(msg.sender == s.safe, NotMySafe());
        updateBalancesBeforeExecution(s);
    }

    // Gnosis Safe Guardian Interface specified at
    // https://docs.safe.global/advanced/smart-account-guards/smart-account-guard-tutorial
    function checkAfterExecution(bytes32 txHash, bool) external {
        ContractStorage storage s = getStorage();
        require(msg.sender == s.safe, NotMySafe());
        if (
            s.preApprovedTxs[txHash].createdAt == 0 ||
            block.timestamp - s.preApprovedTxs[txHash].createdAt < s.ttl
        ) {
            runAssetProtection(s, txHash);
        }
    }

    /**
     * @notice Add a protected asset
     * @param asset The asset to protect
     * @param policy The policy for the asset
     */
    function addProtectedAsset(
        address asset,
        Policy memory policy
    ) external onlyOwner {
        ContractStorage storage s = getStorage();
        validatePolicy(policy);
        require(s.assetsList.add(asset), "Already protected");
        s.assetProtection[asset].rates = policy;
    }

    /**
     * @notice Supports the ERC165 interface
     * @param interfaceId The interface ID
     * @return True if the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) external view virtual returns (bool) {
        return interfaceId == 0xe6d7a83a || interfaceId == 0x01ffc9a7;
    }

    /**
     * @notice Get the TTL
     * @return The TTL
     */
    function getTTL() external view returns (uint256) {
        return getStorage().ttl;
    }

    /**
     * @notice Get the asset policy
     * @param asset The asset
     * @return The policy
     */
    function getAssetPolicy(
        address asset
    ) external view returns (Policy memory) {
        return getStorage().assetProtection[asset].rates;
    }

    /**
     * @notice Revoke a pre-approved transaction
     * @param txHash The transaction hash
     */
    function revokePreApprovedTx(bytes32 txHash) external onlyOwner {
        getStorage().preApprovedTxs[txHash] = PreApprovedTx(0, 0);
    }
}
