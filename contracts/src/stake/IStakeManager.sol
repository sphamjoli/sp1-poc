// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakeManagerTypes} from "./StakeManagerTypes.sol";

/// @title Stake Manager Interface
/// @author brianspha
/// @notice Interface for managing validator stakes and rewards in a bridge validation system
/// @dev Implements a modular staking system with BLS signature support and epoch-based rewards
interface IStakeManager is StakeManagerTypes {
    /// @notice Initialize the stake manager with configuration and validator manager
    /// @param config Initial staking configuration parameters
    /// @param manager Address of the validator manager contract
    /// @dev Can only be called once during deployment
    function initialize(StakeManagerConfig calldata config, address manager) external;

    /// @notice Stake tokens to become a validator
    /// @param params Staking parameters including BLS public key and stake amount
    /// @param proof BLS ownership proof demonstrating control of the public key
    /// @dev Requires prior token approval and minimum stake amount
    function stake(StakeParams calldata params, BlsOwnerShip memory proof) external;

    /// @notice Begin the unstaking process for a validator
    /// @param params see {StakeManagerTypes.UnstakingParams}
    function beginUnstaking(UnstakingParams memory params) external;

    /// @notice Complete unstaking and withdraw tokens after cooldown period
    /// @param who Address of the validator to complete unstaking
    /// @dev Can only be called after minUnstakeDelay has elapsed
    function completeUnstaking(address who) external;

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
    function getStakeVersion(StakeManagerConfig calldata config) external pure returns (bytes32 version);

    /// @notice Distribute rewards to active validators
    /// @param params Reward distribution parameters containing total amount and recipients
    /// @dev Only callable by validator manager, uses epoch-based reward calculation
    function distributeRewards(RewardsParams calldata params) external;

    /// @notice Claim accumulated rewards as a validator
    /// @dev Transfers all pending rewards to the caller
    function claimRewards() external;
}
