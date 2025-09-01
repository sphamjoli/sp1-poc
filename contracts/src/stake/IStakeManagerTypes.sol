// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IValidatorTypes} from "../validator/IValidatorTypes.sol";

/// @title Stake Manager Types
/// @author brianspha
/// @notice Type definitions for the stake manager system
interface IStakeManagerTypes {
    /// @notice Parameters for initiating validator unstaking process
    /// @param stakeAmount Amount of tokens to unstake (partial or full)
    /// @param stakeVersion Configuration version hash that validator is staked under
    /// @param validator Address of the validator initiating unstaking
    struct UnstakingParams {
        uint256 stakeAmount;
        bytes32 stakeVersion;
        address validator;
    }

    /// @notice Parameters for staking tokens as a validator
    /// @param stakeAmount Amount of tokens to stake (must meet minimum requirements)
    /// @param stakeVersion Version hash of the staking configuration
    struct StakeParams {
        uint256 stakeAmount;
        bytes32 stakeVersion;
    }

    /// @notice Validator's balance and staking information
    /// @param balance Pending reward balance available for claiming
    /// @param stakeAmount Current amount of tokens staked
    /// @param stakeVersion Configuration version when validator staked
    /// @param stakeTimestamp When the validator first staked (for reward calculations)
    /// @param stakeExitTimestamp When unstaking was initiated (0 if not unstaking)
    /// @param tokenId NFT id issue to the user when they stake
    /// @param unstakeAmount The amount the validator is unstaking reset after unstaking cycle completes
    /// @param pubkey Validator's BLS public key
    /// @param The last valid epoc the validator got rewards in
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

    /// @notice Parameters for distributing rewards to validators
    /// @param recipients Array of validator information eligible for rewards
    /// @param epoch Rpresents the current epoch
    /// @param epochDuration The time it takes for each epoch to complete
    /// @dev Individual reward amounts calculated based on stake and time
    struct RewardsParams {
        IValidatorTypes.ValidatorInfo[] recipients;
        uint256 epoch;
        uint256 epochDuration;
    }

    /// @notice Configuration parameters for the staking system
    /// @param minStakeAmount Minimum tokens required to become a validator
    /// @param minWithdrawAmount Minimum amount for withdrawal operations
    /// @param minUnstakeDelay Cooldown period before unstaking completion (seconds)
    /// @param correctProofReward Reward amount for correct proof submissions
    /// @param incorrectProofPenalty Penalty amount for incorrect proof submissions
    /// @param maxMissedProofs Maximum missed proofs before potential slashing
    /// @param slashingRate Percentage of stake to slash for severe violations
    /// @param stakingToken Address of the ERC20 token used for staking
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

    /// @notice BLS signature proof for public key ownership
    /// @param signature BLS signature proving ownership of the public key
    /// @param pubkey BLS public key being claimed
    struct BlsOwnerShip {
        uint256[2] signature;
        uint256[4] pubkey;
    }

    /// @notice Internal storage structure for the stake manager
    /// @param balances Mapping of validator addresses to their balance information
    /// @param stakingManagerVersions used to store all the staking versions
    struct SMStorage {
        mapping(address validator => ValidatorBalance balance) balances;
        mapping(bytes32 version => StakeManagerConfig config) stakingManagerVersions;
        uint256[50] __gap;
    }

    /// @notice Parameters for slashing a misbehaving validator
    /// @param validator Address of the validator to slash
    /// @param slashAmount Amount of stake to remove (determined by validator manager)
    struct SlashParams {
        address validator;
        uint256 slashAmount;
    }

    // ========== ERRORS ==========
    /// @notice Thrown when a validators doesnt meet the min performance threshold
    /// for rewards
    error LowPerformance();
    /// @notice Thrown when caller lacks required permissions
    error NotAllowed();

    /// @notice Thrown when a zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when BLS ownership proof verification fails
    error NotOwnerBLS();

    /// @notice Thrown when caller is not the stake manager
    error NotStakeManager();

    /// @notice Thrown when caller is not the validator manager
    error NotValidatorManager();

    /// @notice Thrown when stake version doesn't match current configuration
    error InvalidStakeVersion();

    /// @notice Thrown when stake amount is below minimum requirement
    error MinStakeAmountRequired();

    /// @notice Thrown when insufficient token approval for staking
    error NotApproved();

    /// @notice Thrown when array parameters have mismatched lengths
    error ArrayLengthMismatch();

    /// @notice Thrown when reward distribution has no recipients
    error NoRecipients();

    /// @notice Thrown when calculated reward amount is zero
    error ZeroReward();

    /// @notice Thrown when calculated total doesn't match expected total
    error TotalMismatch();

    /// @notice Thrown when reward token transfer fails
    error RewardTransferFailed();

    /// @notice Thrown when duplicate recipients found in reward distribution
    error DuplicateRecipient();

    /// @notice Thrown when token transfer operation fails
    error TransferFailed();

    /// @notice Thrown when validator has no rewards to claim
    error NoRewardsToClaim();

    /// @notice Thrown when invalid validator address provided for slashing
    error InvalidValidator();

    /// @notice Thrown when slashing amount is zero
    error ZeroSlashAmount();

    /// @notice Thrown when attempting to slash non-existent validator
    error ValidatorNotFound();

    /// @notice Thrown when slashing amount exceeds validator's stake
    error InsufficientStakeToSlash();

    /// @notice Thrown when remaining stake after slashing is below minimum
    error BelowMinimumStake();

    /// @notice thrown when the provided BLS pub key is invalid
    error InvalidPublicKey();

    /// @notice thrown when the provided BLS signature is invalid
    error InvalidSignature();

    /// @notice Thrown when an incorrect staking version is supplied/used
    error InvalidStakingConfig();
    error InvalidBLSSignature();
    error InsufficientTreasury();
    error NoEligibleValidators();
    error NoValidators();
    error NoStakedAmount();
    // ========== EVENTS ==========

    /// @notice Emitted when a validator stakes tokens
    /// @param walletAddress Address of the validator
    /// @param stakeVersion Configuration version hash
    /// @param stakeAmount Amount of tokens staked
    /// @param stakeTimestamp When the staking occurred
    event ValidatorStaked(
        address indexed walletAddress,
        bytes32 indexed stakeVersion,
        uint256 indexed stakeAmount,
        uint256 stakeTimestamp
    );

    /// @notice Emitted when a validator completes unstaking
    /// @param walletAddress Address of the validator
    /// @param stakeVersion Configuration version hash
    /// @param rewards Final reward amount received
    /// @param isPartial if the validator withdrew all their funds
    event ValidatorExit(
        address indexed walletAddress,
        bytes32 indexed stakeVersion,
        uint256 indexed rewards,
        bool isPartial
    );

    /// @notice Emitted when a validator begins unstaking cooldown
    /// @param walletAddress Address of the validator
    /// @param stakeVersion Configuration version hash
    /// @param stakeTimestamp Original stake timestamp
    /// @param stakeExitTimestamp When unstaking was initiated
    event ValidatorCoolDown(
        address indexed walletAddress,
        bytes32 indexed stakeVersion,
        uint256 indexed stakeTimestamp,
        uint256 stakeExitTimestamp
    );

    /// @notice Emitted when a validator claims their rewards
    /// @param validator Address of the validator
    /// @param reward Amount of rewards claimed
    /// @param when Timestamp of the claim
    event ValidatorRewardsClaimed(
        address indexed validator, uint256 indexed reward, uint256 indexed when
    );

    /// @notice Emitted when rewards are allocated to a validator
    /// @param validator Address of the validator
    /// @param reward Amount of rewards allocated
    event ValidatorRewarded(
        address indexed validator,
        uint256 indexed performanceScore,
        uint256 indexed reward,
        uint256 correctAttestations
    );

    /// @notice Emitted when rewards are distributed to validators
    /// @param total Total amount of rewards distributed
    /// @param totalValidator Number of validators that received rewards
    /// @param when Timestamp of the distribution
    event RewardsDistributed(
        uint256 indexed total, uint256 indexed totalValidator, uint256 indexed when
    );

    /// @notice Emitted when stake manager configuration is updated
    /// @param oldConfig Previous configuration
    /// @param newConfig New configuration
    event StakeManagerConfigUpdated(
        StakeManagerConfig indexed oldConfig, StakeManagerConfig indexed newConfig
    );

    /// @notice Emitted when a validator is slashed for misbehavior
    /// @param validator Address of the slashed validator
    /// @param slashAmount Amount of stake slashed
    /// @param originalStake Validator's stake before slashing
    /// @param newStakeAmount Validator's stake after slashing
    /// @param when Timestamp of the slashing
    event ValidatorSlashed(
        address indexed validator,
        uint256 indexed slashAmount,
        uint256 indexed originalStake,
        uint256 newStakeAmount,
        uint256 when
    );
}
