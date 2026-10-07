// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStakeManagerTypes} from "./IStakeManagerTypes.sol";

/// @title Stake Manager Interface
/// @author brianspha
/// @notice Interface for managing validator stakes and rewards in a bridge validation system
/// @dev Implements a modular staking system with BLS signature support and epoch-based rewards
interface IStakeManager is IStakeManagerTypes {
    /// @notice Initialize the stake manager with configuration and owner
    /// @param config Initial staking configuration parameters
    /// @param owner Address that will own and wire the contract after deployment
    /// @dev Can only be called once during deployment
    function initialize(StakeManagerConfig calldata config, address owner) external;

    /// @notice Stake tokens to become a validator
    /// @param params Staking parameters including BLS public key and stake amount
    /// @param proof BLS ownership proof demonstrating control of the public key
    /// @dev Requires prior token approval, exact token receipt, and minimum initial stake.
    ///      Top-ups preserve the initial timestamp and are unavailable during pending exits.
    function stake(StakeParams calldata params, BlsOwnerShip memory proof) external;

    /// @notice Begin the unstaking process for a validator
    /// @dev Active validators enter cooldown. Inactive validators may exit immediately.
    ///      Principal and accrued rewards remain separate until payout.
    /// @param params see {IStakeManagerTypes.UnstakingParams}
    function beginUnstaking(UnstakingParams memory params) external;

    /// @notice Complete unstaking and withdraw tokens after cooldown period
    /// @dev Active exits require minUnstakeDelay. Full exits pay principal and all rewards,
    ///      then burn the NFT. Partial exits pay only principal and restore active status.
    function completeUnstaking() external;

    /// @notice Update staking configuration parameters
    /// @param config New configuration parameters
    /// @dev Only callable by authorized admin role
    function upgradeStakeConfig(StakeManagerConfig calldata config) external;

    /// @notice Slash a validator's stake for misbehavior
    /// @param params Slashing parameters including validator and amount
    /// @dev Only callable by validator manager, slashed funds remain in protocol
    function slashValidator(SlashParams calldata params) external;

    /// @notice Get pending reward balance for a validator
    /// @param validator Address of the validator
    /// @return amount Pending reward amount available for claiming
    function getLatestRewards(address validator) external view returns (uint256 amount);

    /// @notice Calculate stake version hash for given configuration
    /// @param config Configuration to hash
    /// @return version Deterministic hash of the configuration
    function getStakeVersion(StakeManagerConfig calldata config)
        external
        pure
        returns (bytes32 version);

    /// @notice Distribute rewards to active validators
    /// @param params Reward distribution parameters containing total amount and recipients
    /// @dev Only callable by validator manager. Each allocated reward, including bonuses,
    ///      must be backed by unallocated token reserves; insufficient funding reverts atomically.
    function distributeRewards(RewardsParams calldata params) external;

    /// @notice Claim accumulated rewards as a validator
    /// @dev Transfers all pending rewards to the caller and reduces reserves and allocated
    ///      liabilities before the token call. Principal remains unavailable for reward payouts.
    function claimRewards() external;

    /// @notice Allows for pausing contract operations
    /// @dev OnlyOwner can make this call
    function pause() external;

    /// @notice Allows for unpausing of contract operations
    /// @dev OnlyOwner can make this call
    function unPause() external;

    /// @notice Hash proof of possession message to curve point
    /// @param blsPubkey The BLS public key to prove possession of
    /// @return The message hashed to a curve point for BLS verification
    function proofOfPossessionMessage(uint256[4] memory blsPubkey)
        external
        view
        returns (uint256[2] memory);

    /// @notice Updates the Validator manager address
    /// @param manager The new Validator address
    /// @dev Only owner can make this call
    function updateValidatorManager(address manager) external;

    /// @notice Get ValidatorBalance
    /// @param validator The validators address
    /// @return  info {IStakeManagerTypes.ValidatorBalance}
    function validatorBalance(address validator)
        external
        view
        returns (ValidatorBalance calldata info);

    ///@notice Allows owner to topup reward token balance on the contract
    ///@dev Only owner can make this call
    function transferToken(address token, uint256 amount) external;

    /// @notice Withdraw surplus not committed to principal or funded reward reserves
    /// @dev Owner-only. Total token assets must cover principal plus all reward funding,
    ///      including allocated liabilities. Only the remaining surplus may be transferred.
    /// @param token ERC20 token
    /// @param amount Max amount to withdraw
    function sweepExcess(address token, uint256 amount) external;
}
