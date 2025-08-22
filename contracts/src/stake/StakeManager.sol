// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IStakeManager} from "./IStakeManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {BLS} from "solbls/BLS.sol";
import {StakeManagerStorage} from "./StakeManagerStorage.sol";
import {ArrayContainsLib} from "../libs/ArrayContainsLib.sol";

/// @title Stake Manager
/// @notice Manages validator stakes and rewards for bridge validation system
/// @dev Implements pull-based rewards and BLS signature verification
contract StakeManager is
    IStakeManager,
    Initializable,
    Ownable,
    UUPSUpgradeable,
    ERC721Enumerable,
    StakeManagerStorage
{
    using BLS for *;
    using ArrayContainsLib for address[];

    /// @notice Restricts access to validator manager only
    modifier onlyValidatorManager() {
        require(msg.sender == VALIDATOR_MANAGER, NotValidatorManager());
        _;
    }

    /// @notice Chain ID where this contract is deployed
    uint256 public immutable CHAIN_ID;

    /// @notice Counter for NFT token IDs
    uint256 public COUNTER;

    /// @notice Active staking configuration
    StakeManagerConfig public ACTIVE_STAKING_CONFIG;

    /// @notice Address of the validator manager contract
    address public VALIDATOR_MANAGER;

    /// @notice Duration of each reward epoch
    uint256 public immutable EPOCH_DURATION;

    /// @notice Reward rate per epoch
    uint256 public immutable REWARD_RATE;

    /// @notice Scaling factor for reward calculations
    uint64 public immutable SCALING_FACTOR;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC721("SP1 Bridge Poc", "SBP") Ownable(msg.sender) {
        CHAIN_ID = block.chainid;
        EPOCH_DURATION = 2 minutes;
        // ~5% annually
        REWARD_RATE = 1900;
        SCALING_FACTOR = 1e18;
        _disableInitializers();
    }

    /// @inheritdoc IStakeManager
    function initialize(StakeManagerConfig memory config, address manager) external override initializer {
        emit StakeManagerConfigUpdated(ACTIVE_STAKING_CONFIG, config);
        ACTIVE_STAKING_CONFIG = config;
        VALIDATOR_MANAGER = manager;
        SMStorage storage $ = __loadStorage();
        $.stakingManagerVersions[getStakeVersion(config)] = config;
        __UUPSUpgradeable_init();
    }

    /// @inheritdoc IStakeManager
    function stake(StakeParams memory params, BlsOwnerShip memory proof) external override {
        (bool pairingSuccess, bool callSuccess) = BLS.verifySingle(proof.signature, proof.pubkey, proof.message);
        IERC20 token = IERC20(ACTIVE_STAKING_CONFIG.stakingToken);
        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[msg.sender];
        StakeManagerConfig memory config = $.stakingManagerVersions[params.stakeVersion];

        require(pairingSuccess && callSuccess, NotOwnerBLS());
        require(params.stakeVersion == getStakeVersion(ACTIVE_STAKING_CONFIG), InvalidStakeVersion());
        require(params.stakeAmount >= ACTIVE_STAKING_CONFIG.minStakeAmount, MinStakeAmountRequired());
        require(token.allowance(msg.sender, address(this)) >= params.stakeAmount, NotApproved());
        require(token.transferFrom(msg.sender, address(this), params.stakeAmount), TransferFailed());
        require(config.minStakeAmount > 0, InvalidStakingConfig());

        validator.stakeAmount += params.stakeAmount;
        validator.stakeVersion = params.stakeVersion;
        validator.stakeTimestamp = block.timestamp;
        validator.pubkey = params.pubkey;

        _mint(msg.sender, COUNTER++);
        emit ValidatorStaked(msg.sender, validator.stakeVersion, validator.stakeAmount, block.timestamp);
    }

    /// @inheritdoc ERC721
    /// @dev Transfers are disabled for validator NFTs
    function transferFrom(address, address, uint256) public pure override(IERC721, ERC721) {
        revert NotAllowed();
    }

    /// @inheritdoc ERC721
    /// @dev Approvals are disabled for validator NFTs
    function approve(address, uint256) public pure override(IERC721, ERC721) {
        revert NotAllowed();
    }

    /// @inheritdoc IStakeManager
    function beginUnstaking(UnstakingParams memory params) external override onlyValidatorManager {
        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[params.validator];
        StakeManagerConfig memory config = $.stakingManagerVersions[params.stakeVersion];
        require(config.minStakeAmount > 0, InvalidStakingConfig());
        require(validator.stakeAmount > 0, ValidatorNotFound());
        // // Already unstaking so we revert
        require(validator.stakeExitTimestamp == 0, NotAllowed());
        require(validator.stakeAmount >= config.minStakeAmount);
        validator.stakeExitTimestamp = block.timestamp;
        validator.unstakeAmount = params.stakeAmount;
        emit ValidatorCoolDown(params.validator, validator.stakeVersion, validator.stakeTimestamp, block.timestamp);
    }

    /// @inheritdoc IStakeManager
    function completeUnstaking(address who) external override onlyValidatorManager {
        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[who];

        require(validator.stakeAmount > 0, ValidatorNotFound());
        require(validator.stakeExitTimestamp > 0, NotAllowed());
        require(block.timestamp >= validator.stakeExitTimestamp + ACTIVE_STAKING_CONFIG.minUnstakeDelay, NotAllowed());
        require(validator.unstakeAmount > 0, NotAllowed());

        uint256 totalAmount = validator.unstakeAmount;
        uint256 rewardAmount = validator.balance;
        bool partialExit = true;
        if (validator.stakeAmount >= validator.unstakeAmount) {
            validator.stakeAmount -= validator.unstakeAmount;
        } else if (validator.balance >= validator.unstakeAmount) {
            validator.balance -= validator.unstakeAmount;
        } else {
            uint256 remainingAmount = validator.unstakeAmount - validator.balance;
            validator.balance = 0;
            validator.stakeAmount -= remainingAmount;
        }

        if (validator.stakeAmount == 0) {
            delete $.balances[who];
            partialExit = false;
        } else {
            require(validator.stakeAmount >= ACTIVE_STAKING_CONFIG.minStakeAmount, BelowMinimumStake());
            validator.unstakeAmount = 0;
            validator.stakeExitTimestamp = 0;
        }

        IERC20 token = IERC20(ACTIVE_STAKING_CONFIG.stakingToken);
        require(token.transfer(who, totalAmount), TransferFailed());

        emit ValidatorExit(who, validator.stakeVersion, rewardAmount, partialExit);
    }

    /// @inheritdoc IStakeManager
    function upgradeStakeConfig(StakeManagerConfig calldata config) external override onlyOwner {
        emit StakeManagerConfigUpdated(ACTIVE_STAKING_CONFIG, config);
        ACTIVE_STAKING_CONFIG = config;
    }

    /// @inheritdoc IStakeManager
    function slashValidator(SlashParams calldata params) external override onlyValidatorManager {
        require(params.slashAmount > 0, ZeroSlashAmount());
        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[params.validator];

        require(validator.stakeAmount > 0, ValidatorNotFound());
        uint256 balance = validator.stakeAmount + validator.balance;
        require(balance >= params.slashAmount, InsufficientStakeToSlash());

        uint256 originalStake = validator.stakeAmount;

        if (validator.stakeAmount >= params.slashAmount) {
            validator.stakeAmount -= params.slashAmount;
        } else if (validator.balance >= params.slashAmount) {
            validator.balance -= params.slashAmount;
        } else {
            uint256 remainingSlash = params.slashAmount - validator.balance;
            validator.balance = 0;
            validator.stakeAmount -= remainingSlash;
        }

        if (validator.stakeAmount > 0) {
            require(validator.stakeAmount >= ACTIVE_STAKING_CONFIG.minStakeAmount, BelowMinimumStake());
        }

        emit ValidatorSlashed(
            params.validator, params.slashAmount, originalStake, validator.stakeAmount, block.timestamp
        );
    }

    /// @inheritdoc IStakeManager
    function distributeRewards(RewardsParams calldata params) external override onlyValidatorManager {
        SMStorage storage $ = __loadStorage();
        uint256 calculatedTotal;
        uint256 length = params.recipients.length;
        address[] memory seen = new address[](length);

        for (uint256 i = 0; i < length;) {
            address recipient = params.recipients[i];
            require(!seen.contains(recipient), DuplicateRecipient());
            seen[i] = recipient;

            ValidatorBalance storage validator = $.balances[recipient];

            uint256 epochsStaked = (block.timestamp - validator.stakeTimestamp) / EPOCH_DURATION;
            uint256 amount = (validator.stakeAmount * REWARD_RATE * epochsStaked) / SCALING_FACTOR;
            require(amount > 0, ZeroReward());
            calculatedTotal += amount;

            validator.balance += amount;

            emit ValidatorRewarded(recipient, amount);

            ++i;
        }

        require(calculatedTotal == params.totalReward, TotalMismatch());
        emit RewardsDistributed(calculatedTotal, length, block.timestamp);
    }

    /// @inheritdoc IStakeManager
    function claimRewards() external override {
        SMStorage storage $ = __loadStorage();
        ValidatorBalance storage validator = $.balances[msg.sender];

        require(validator.balance > 0, NoRewardsToClaim());
        uint256 amount = validator.balance;
        validator.balance = 0;

        IERC20 token = IERC20(ACTIVE_STAKING_CONFIG.stakingToken);
        require(token.transfer(msg.sender, amount), TransferFailed());

        emit ValidatorRewardsClaimed(msg.sender, amount, block.timestamp);
    }

    /// @inheritdoc IStakeManager
    function getLatestRewards(address validator) external view override returns (uint256) {
        SMStorage storage $ = __loadStorage();
        return $.balances[validator].balance;
    }

    /// @inheritdoc IStakeManager
    function getStakeVersion(StakeManagerConfig memory config) public pure override returns (bytes32) {
        return keccak256(
            abi.encode(
                config.minStakeAmount,
                config.minWithdrawAmount,
                config.minUnstakeDelay,
                config.correctProofReward,
                config.incorrectProofPenalty,
                config.maxMissedProofs,
                config.slashingRate,
                config.stakingToken
            )
        );
    }

    /// @notice Authorize contract upgrades
    /// @dev Only owner can authorize upgrades per UUPS pattern
    /// @param newImplementation Address of new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
