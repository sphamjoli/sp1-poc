// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IBridgeUtils} from "./IBridgeTypes.sol";

/// @title IBridge
/// @notice Interface for a POC SP1-powered cross-chain bridge contract
/// @dev Extends IBridgeUtils with bridge-specific functionality
interface IBridge is IBridgeUtils {
    /// @notice Initialize the bridge contract
    /// @param owner Initial owner of the contract
    function initialize(address owner) external;

    /// @notice Deposit native ETH or ERC20 token
    /// @param depositParams Struct containing deposit parameters (amount taken from msg.value)
    function deposit(DepositParams calldata depositParams) external payable;

    /// @notice Claim bridged assets using SP1 proof verification
    /// @param claimParams Struct containing all claim parameters and proof data
    function claim(ClaimParams calldata claimParams) external;

    /// @notice Emergency rescue of stuck ETH from contract
    /// @param amount Amount of ETH to rescue
    /// @param to Recipient address for rescued funds
    function rescueEth(uint256 amount, address to) external;

    /// @notice Emergency rescue of stuck ERC20 tokens from contract
    /// @param token Token contract address to rescue
    /// @param amount Amount of tokens to rescue
    /// @param to Recipient address for rescued tokens
    function rescueTokens(address token, uint256 amount, address to) external;

    /// @notice Pause all bridge operations
    function pause() external;

    /// @notice Resume all bridge operations
    function unpause() external;

    /// @notice Get contract balance for specified token
    /// @param token Token address to check balance (zero address for ETH)
    /// @return Current balance amount
    function getBalance(address token) external view returns (uint256);
}
