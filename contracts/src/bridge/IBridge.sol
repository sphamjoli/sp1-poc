// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IBridgeTypes} from "./BridgeTypes.sol";

/// @title IBridge
/// @notice Interface for a proof-driven cross-chain bridge
/// @dev Extends IBridgeTypes for shared params, events, and errors
interface IBridge is IBridgeTypes {
    /// @notice Initialize the bridge
    /// @dev Should be called once on the proxy
    /// @param owner Address that will receive ownership
    function initialize(address owner) external;

    /// @notice Deposit native ETH or ERC20 for bridging
    /// @dev If token is zero address, amount must equal msg.value
    /// @param depositParams Deposit parameters container
    function deposit(DepositParams calldata depositParams) external payable;

    /// @notice Claim bridged assets on the destination chain
    /// @dev Verifies source root and Merkle proof, then transfers funds
    /// @param claimParams Claim parameters and proof data
    function claim(ClaimParams calldata claimParams) external;

    /// @notice Rescue stuck ETH held by the contract
    /// @dev Owner-only administrative function
    /// @param amount Amount of ETH to withdraw
    /// @param to Recipient of the rescued ETH
    function rescueEth(uint256 amount, address to) external;

    /// @notice Rescue stuck ERC20 tokens held by the contract
    /// @dev Owner-only administrative function
    /// @param token ERC20 token address to withdraw
    /// @param amount Amount of tokens to withdraw
    /// @param to Recipient of the rescued tokens
    function rescueTokens(address token, uint256 amount, address to) external;

    /// @notice Pause bridge operations
    /// @dev Intended for emergency use
    function pause() external;

    /// @notice Unpause bridge operations
    function unpause() external;

    /// @notice Get contract balance for a token or ETH
    /// @param token Token address, or zero address for ETH
    /// @return balance Current balance held by the contract
    function getBalance(address token) external view returns (uint256 balance);

    /// @notice Update the validator manager used to verify source roots
    /// @dev Governance or owner should control this address
    /// @param validatorManager Address of the validator manager contract
    function updateValidatorManager(address validatorManager) external;
}
