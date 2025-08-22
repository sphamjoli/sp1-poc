// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

///
/// @title IValidatorGovernance
/// @author Brianshpa
/// @notice Governance interface for validator system administration
///
/// OVERVIEW:
/// Provides administrative functions for managing the validator system,
/// including parameter updates, emergency controls, and validator set
/// management. Initially controlled by multisig, eventually by token governance.
///
interface IValidatorGovernance {
    /// @notice Emergency pause all validator operations
    /// @dev Prevents new stakes, attestations, and unstaking
    function emergencyPause() external;

    /// @notice Resume validator operations after pause
    function emergencyUnpause() external;

    /// @notice Force slash validator for provable malicious behavior
    /// @param validator Validator to slash
    /// @param slashAmount Amount to slash
    /// @param evidence IPFS hash of evidence
    /// @dev Used for manual intervention in clear fraud cases
    function forceSlash(address validator, uint256 slashAmount, bytes32 evidence) external;

    /// @notice Update reward distribution contract
    /// @param newRewardDistributor Address of new reward distribution contract
    function setRewardDistributor(address newRewardDistributor) external;

    /// @notice Update SP1 verification contract
    /// @param newVerifier Address of new SP1 verification contract
    function setVerificationContract(address newVerifier) external;

    /// @notice Recover tokens sent to contract by mistake
    /// @param token Token contract address (0x0 for ETH)
    /// @param to Recovery destination
    /// @param amount Amount to recover
    function recoverTokens(address token, address to, uint256 amount) external;

    /// @notice Check if system is paused
    /// @return paused True if system is paused
    function isPaused() external view returns (bool paused);

    /// @notice Get current governance address
    /// @return governance Address of current governance
    function getGovernance() external view returns (address governance);

    /// @notice Transfer governance to new address
    /// @param newGovernance New governance address
    function transferGovernance(address newGovernance) external;
}
