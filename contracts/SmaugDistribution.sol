// SPDX-License-Identifier: Business Source License (BSL 1.1)

pragma solidity =0.8.28;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import "@peeramid-labs/eds/src/interfaces/IDistribution.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@peeramid-labs/eds/src/abstracts/CodeIndexer.sol";
import {ShortStrings, ShortString} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import "@peeramid-labs/eds/src/abstracts/CloneDistribution.sol";
import {Policy, Smaug} from "./Smaug.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface SanctionsList {
    function isSanctioned(address addr) external view returns (bool);
}

/**
 * @title MAODistribution
 * @dev This contract implements the IDistribution and CodeIndexer interfaces. It uses the Clones library for address cloning.
 *
 * @notice The contract is responsible for creating and managing DAOs and Rankify distributions.
 * @author Peeramid Labs, 2024
 */
contract SmaugDistribution is CloneDistribution, Ownable {
    event GratitudeSet(uint256 newGratitude);
    event BeneficiarySet(address newBeneficiary);

    struct InstantiateArguments {
        address admin;
        uint256 ttl;
        address safe;
        address[] assets;
        Policy[] policies;
    }

    event SmaugInstantiated(
        address indexed smaug,
        address indexed distributor,
        InstantiateArguments args
    );

    address private immutable _smaug;
    ShortString private immutable _distributionName;
    uint256 private immutable _distributionVersion;
    address private immutable _usdc;
    address constant SANCTIONS_CONTRACT =
        0x40C57923924B5c5c5455c48D93317139ADDaC8fb;
    address private _dao;

    uint256 public gratitude = 200 * 10 ** 6; // 200 USDC

    /**
     * @notice Initializes the contract with the provided parameters and performs necessary checks.
     * @dev Retrieves contract addresses from a contract index using the provided identifiers
     *      and initializes the distribution system.
     * @dev WARNING: distributionName must be less then 31 bytes long to comply with ShortStrings immutable format
     * @param smaug Address of the Smaug contract
     */
    constructor(
        address smaug,
        ShortString distributionName,
        uint256 distributionVersion,
        address usdc,
        address owner,
        address beneficiary
    ) Ownable(owner) {
        _smaug = smaug;
        require(smaug != address(0), "Smaug address is required");
        _distributionName = distributionName;
        _distributionVersion = distributionVersion;
        _usdc = usdc;
        _dao = beneficiary;
    }

    /**
     * @notice Instantiates a new instance with the provided data.
     * @param data The initialization data for the new instance, typeof {DistributorArguments}.
     * @return instances An array of addresses representing the new instances.
     * @return distributionName A bytes32 value representing the name of the distribution.
     * @return distributionVersion A uint256 value representing the version of the distribution.
     * @dev `instances` array contents: GovernanceToken, Gov Token AccessManager, Rankify Diamond, 8x Rankify Diamond facets, RankTokenAccessManager, RankToken
     */
    /* @inheritdoc IDistribution */
    function instantiate(
        bytes memory data
    )
        public
        override
        returns (
            address[] memory instances,
            bytes32 distributionName,
            uint256 distributionVersion
        )
    {
        if (msg.sender != owner() && msg.sender != _dao)
            require(
                IERC20(_usdc).transferFrom(msg.sender, _dao, gratitude),
                "Transfer failed"
            );

        (instances, distributionName, distributionVersion) = sources();

        InstantiateArguments memory args = abi.decode(
            data,
            (InstantiateArguments)
        );

        Smaug newInstance = Smaug(instances[0]);
        newInstance.initialize(
            args.admin,
            args.ttl,
            args.safe,
            args.assets,
            args.policies
        );
        require(
            !SanctionsList(SANCTIONS_CONTRACT).isSanctioned(msg.sender),
            "Sender is sanctioned"
        );

        emit SmaugInstantiated(address(newInstance), msg.sender, args);
    }

    /* @inheritdoc IDistribution */
    function contractURI()
        public
        pure
        virtual
        override
        returns (string memory)
    {
        return "";
    }

    function sources()
        internal
        view
        virtual
        override
        returns (address[] memory, bytes32, uint256)
    {
        address[] memory source = new address[](1);
        source[0] = _smaug;
        return (
            source,
            ShortString.unwrap(_distributionName),
            _distributionVersion
        );
    }

    function setGratitude(uint256 newGratitude) external onlyOwner {
        gratitude = newGratitude;
        emit GratitudeSet(newGratitude);
    }

    function setBeneficiary(address newBeneficiary) external onlyOwner {
        _dao = newBeneficiary;
        emit BeneficiarySet(newBeneficiary);
    }
}
