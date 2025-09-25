// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IValidatorTypes} from "../validator/IValidatorTypes.sol";

/// @title Stake Manager Types
/// @author brianspha
/// @notice Common types, events, and errors for the staking subsystem
/// @dev Shared by stake manager contracts for a consistent ABI
interface IStakeManagerTypes {
    /// @notice Parameters for initiating an unstake
    /// @param stakeAmount Amount of stake to begin unstaking
    struct UnstakingParams {
        uint256 stakeAmount;
    }

    /// @notice Parameters for staking
    /// @param stakeAmount Amount of tokens to stake
    /// @param stakeVersion Version hash of the active staking config
    struct StakeParams {
        uint256 stakeAmount;
        bytes32 stakeVersion;
    }

    /// @notice Validator balance and staking state
    /// @param balance Pending rewards available to claim
    /// @param stakeAmount Amount currently staked
    /// @param stakeVersion Config version used when staking
    /// @param stakeTimestamp Timestamp of initial stake
    /// @param stakeExitTimestamp Timestamp when unstake was initiated (0 if none)
    /// @param tokenId NFT id issued at stake time
    /// @param unstakeAmount Amount currently in the unstake process
    /// @param lastRewardEpoch Last epoch in which rewards were earned
    /// @param pubkey Validator BLS public key
    struct ValidatorBalance {
        uint256 balance;
        uint256 stakeAmount;
        bytes32 stakeVersion;
        uint256 stakeTimestamp;
        uint256 stakeExitTimestamp;
        uint256 unstakeAmount;
        uint256 tokenId;
        uint256 lastRewardEpoch;
        uint256[4] pubkey;
    }

    /// @notice Parameters for distributing rewards
    /// @param recipients Validators eligible for rewards
    /// @param epoch Current epoch id
    /// @param epochDuration Epoch duration in seconds
    /// @dev Individual rewards typically depend on stake and time
    struct RewardsParams {
        IValidatorTypes.ValidatorInfo[] recipients;
        uint256 epoch;
        uint256 epochDuration;
    }

    /// @notice Staking configuration
    /// @param minStakeAmount Minimum required stake
    /// @param minWithdrawAmount Minimum amount that can be withdrawn
    /// @param minUnstakeDelay Unstake cooldown in seconds
    /// @param correctProofReward Reward for correct proof submission
    /// @param incorrectProofPenalty Penalty for incorrect proof submission
    /// @param maxMissedProofs Max missed proofs allowed before action
    /// @param slashingRate Slash percentage for severe violations
    /// @param stakingToken ERC20 token used for staking
    struct StakeManagerConfig {
        uint256 minStakeAmount;
        uint256 minWithdrawAmount;
        uint256 minUnstakeDelay;
        uint256 correctProofReward;
        uint256 incorrectProofPenalty;
        uint32 maxMissedProofs;
        uint256 slashingRate;
        address stakingToken;
    }

    /// @notice BLS ownership proof
    /// @param signature BLS signature
    /// @param pubkey BLS public key being proven
    struct BlsOwnerShip {
        uint256[2] signature;
        uint256[4] pubkey;
    }

    /// @notice Internal storage layout
    /// @param balances Map of validator address to balance data
    /// @param stakingManagerVersions Map of version hash to config
    /// @param rewardReserves Token reserves available for rewards
    /// @param principal Total staked principal per token
    /// @param __gap Reserved for future storage
    struct SMStorage {
        mapping(address validator => ValidatorBalance balance) balances;
        mapping(bytes32 version => StakeManagerConfig config) stakingManagerVersions;
        mapping(address token => uint256) rewardReserves;
        mapping(address token => uint256) principal;
        uint256[49] __gap;
    }

    /// @notice Parameters for slashing
    /// @param validator Address to slash
    /// @param slashAmount Amount of stake to slash
    struct SlashParams {
        address validator;
        uint256 slashAmount;
    }

    /// @notice Validator performance below reward threshold
    error LowPerformance();

    /// @notice Caller lacks permission
    error NotAllowed();

    /// @notice Zero address not allowed
    error ZeroAddress();

    /// @notice BLS ownership proof failed
    error NotOwnerBLS();

    /// @notice Caller is not the stake manager
    error NotAdminManager();

    /// @notice Caller is not the validator manager
    error NotValidatorManager();

    /// @notice Provided stake version is invalid
    error InvalidStakeVersion();

    /// @notice Stake amount below minimum
    error MinStakeAmountRequired();

    /// @notice Unstake amount exceeds current stake
    error AmountExceedsStake();

    /// @notice Insufficient token allowance for staking
    error NotApproved();

    /// @notice Array parameter lengths mismatch
    error ArrayLengthMismatch();

    /// @notice No recipients provided for reward distribution
    error NoRecipients();

    /// @notice Computed reward is zero
    error ZeroReward();

    /// @notice Totals do not match expected values
    error TotalMismatch();

    /// @notice Reward token transfer failed
    error RewardTransferFailed();

    /// @notice Duplicate recipients detected
    error DuplicateRecipient();

    /// @notice Generic token transfer failed
    error TransferFailed();

    /// @notice Top-up did not increase reserves
    error NotReservesRecieved();

    /// @notice No access to reserves
    error NoAccessReserves();

    /// @notice No rewards available to claim
    error NoRewardsToClaim();

    /// @notice Invalid validator address
    error InvalidValidator();

    /// @notice Slash amount is zero
    error ZeroSlashAmount();

    /// @notice Validator not found
    error ValidatorNotFound();

    /// @notice Slash exceeds validator stake
    error InsufficientStakeToSlash();

    /// @notice Remaining stake after slash below minimum
    error BelowMinimumStake();

    /// @notice Invalid BLS public key
    error InvalidPublicKey();

    /// @notice Invalid BLS signature
    error InvalidSignature();

    /// @notice Contract has no reward reserves
    error NoRewards();

    /// @notice Staking configuration invalid
    error InvalidStakingConfig();

    /// @notice Invalid BLS signature provided
    error InvalidBLSSignature();

    /// @notice Treasury balance insufficient
    error InsufficientTreasury();

    /// @notice No eligible validators for rewards
    error NoEligibleValidators();

    /// @notice No validators present
    error NoValidators();

    /// @notice No staked amount for operation
    error NoStakedAmount();

    /// @notice Division operation failed
    error DivisionFailed();

    /// @notice Epoch duration mismatch
    error EpochDurationMisMatch();

    /// @notice Validator already rewarded in this epoch
    error AlreadyRewardedThisEpoch();

    /// @notice Staking version differs from validator’s current version
    error MigrateToNewVersion();

    /// @notice Emitted when a validator stakes
    /// @param walletAddress Validator address
    /// @param stakeVersion Configuration version hash
    /// @param stakeAmount Amount staked
    /// @param stakeTimestamp Timestamp of staking
    event ValidatorStaked(
        address indexed walletAddress,
        bytes32 indexed stakeVersion,
        uint256 indexed stakeAmount,
        uint256 stakeTimestamp
    );

    /// @notice Emitted when a validator finishes an exit
    /// @param walletAddress Validator address
    /// @param stakeVersion Configuration version hash
    /// @param rewards Final rewards paid
    /// @param isPartial True if a partial exit
    event ValidatorExit(
        address indexed walletAddress,
        bytes32 indexed stakeVersion,
        uint256 indexed rewards,
        bool isPartial
    );

    /// @notice Emitted when an unstake cooldown begins
    /// @param walletAddress Validator address
    /// @param stakeVersion Configuration version hash
    /// @param stakeTimestamp Original stake timestamp
    /// @param stakeExitTimestamp Cooldown start timestamp
    event ValidatorCoolDown(
        address indexed walletAddress,
        bytes32 indexed stakeVersion,
        uint256 indexed stakeTimestamp,
        uint256 stakeExitTimestamp
    );

    /// @notice Emitted when the validator manager address changes
    /// @param currentValidatorManager Previous manager address
    /// @param newValidatorManager New manager address
    event UpdatedValidatorManager(
        address indexed currentValidatorManager,
        address indexed newValidatorManager
    );

    /// @notice Emitted when a validator claims rewards
    /// @param validator Validator address
    /// @param reward Amount claimed
    /// @param when Claim timestamp
    event ValidatorRewardsClaimed(
        address indexed validator,
        uint256 indexed reward,
        uint256 indexed when
    );

    /// @notice Emitted when rewards are allocated to a validator
    /// @param validator Validator address
    /// @param reward Amount allocated
    /// @param correctAttestations Count of correct attestations
    event ValidatorRewarded(
        address indexed validator,
        uint256 indexed reward,
        uint256 correctAttestations
    );

    /// @notice Emitted when rewards are distributed
    /// @param total Total rewards distributed
    /// @param totalValidator Number of validators paid
    /// @param when Distribution timestamp
    event RewardsDistributed(
        uint256 indexed total,
        uint256 indexed totalValidator,
        uint256 indexed when
    );

    /// @notice Emitted when stake manager config updates
    /// @param oldConfig Previous config
    /// @param newConfig New config
    event StakeManagerConfigUpdated(
        StakeManagerConfig indexed oldConfig,
        StakeManagerConfig indexed newConfig
    );

    /// @notice Emitted when a validator is slashed
    /// @param validator Validator address
    /// @param slashAmount Amount slashed
    /// @param originalStake Stake before slashing
    /// @param newStakeAmount Stake after slashing
    /// @param when Timestamp of slashing
    event ValidatorSlashed(
        address indexed validator,
        uint256 indexed slashAmount,
        uint256 indexed originalStake,
        uint256 newStakeAmount,
        uint256 when
    );

    /// @notice Emitted when rewards reserves are topped up
    /// @param token ERC20 token used for rewards
    /// @param amountReceived Amount received by the contract
    /// @param funder Address providing the funds
    event RewardTopUp(
        address indexed token,
        uint256 amountReceived,
        address indexed funder
    );
}
