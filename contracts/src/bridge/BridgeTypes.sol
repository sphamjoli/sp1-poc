// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SparseMerkleTree} from "../libs/LocalExitTreeLib.sol";

/// @title BridgeTypes
/// @author brianspha
/// @notice Common types, events, and errors for the bridge
/// @dev Shared base interface for consistent ABI and logging
interface IBridgeTypes {
    /// @notice Bridge storage layout
    /// @dev Append-only fields to preserve upgrade safety
    struct Storage {
        /// @notice Sparse Merkle tree for deposits
        /// @dev Tracks deposit leaves on the source chain
        SparseMerkleTree.Bytes32SMT depositTree;
        /// @notice Sparse Merkle tree for claims
        /// @dev Tracks claim/nullifier leaves on the destination chain
        SparseMerkleTree.Bytes32SMT claimTree;
        /// @notice Next deposit index
        /// @dev Monotonically increasing counter
        uint256 depositCounter;
        /// @notice Next claim index
        /// @dev Monotonically increasing counter
        uint256 claimCounter;
        /// @notice Root acceptance map per source chain
        /// @dev validRoots[chainId][root] == true if verified/accepted
        mapping(uint256 => mapping(bytes32 => bool)) validRoots;
        /// @notice Claimed deposits bitmap
        /// @dev Keyed by keccak256(abi.encode(sourceChain, depositIndex))
        mapping(bytes32 => bool) claimed;
        /// @notice Reserved storage gap for upgrades
        uint256[50] __gap;
    }

    /// @notice Deposit parameters
    /// @param amount Amount to deposit
    /// @param token ERC20 token address (zero for native ETH)
    /// @param to Recipient on the destination chain
    /// @param destinationChain Chain ID where assets will be claimed
    struct DepositParams {
        uint256 amount;
        address token;
        address to;
        uint256 destinationChain;
    }

    /// @notice Claim leaf data recorded in the claim tree
    /// @param sourceDepositIndex Deposit index on the source chain
    /// @param sourceChain Source chain ID
    /// @param sourceRoot Source deposit tree root used for verification
    /// @param claimer Caller that executed the claim
    /// @param recipient Recipient of the assets
    /// @param amount Amount claimed
    /// @param token Token being claimed
    /// @param timestamp Block timestamp when processed
    /// @param destinationChain Destination chain ID (current chain)
    struct ClaimLeaf {
        uint256 sourceDepositIndex;
        uint256 sourceChain;
        bytes32 sourceRoot;
        address claimer;
        address recipient;
        uint256 amount;
        address token;
        uint256 timestamp;
        uint256 destinationChain;
    }

    /// @notice Claim parameters
    /// @param depositIndex Deposit index on the source chain
    /// @param sourceChain Source chain ID
    /// @param token Token to claim
    /// @param to Recipient address on this chain
    /// @param amount Amount to claim
    /// @param sourceRoot Source deposit tree root to verify against
    /// @param proof Merkle inclusion proof from the source deposit tree
    struct ClaimParams {
        uint256 depositIndex;
        uint32 sourceChain;
        address token;
        address to;
        uint256 amount;
        bytes32 sourceRoot;
        SparseMerkleTree.Proof proof;
    }

    /// @notice Emitted on deposit on the source chain
    /// @param who Depositor address
    /// @param amount Amount deposited
    /// @param token Token address (zero for native ETH)
    /// @param to Destination recipient
    /// @param sourceChain Source chain ID
    /// @param destinationChain Destination chain ID
    /// @param depositIndex Assigned deposit index
    /// @param depositRoot New deposit tree root after insertion
    event Deposit(
        address indexed who,
        uint256 amount,
        address indexed token,
        address to,
        uint256 sourceChain,
        uint256 destinationChain,
        uint256 depositIndex,
        bytes32 indexed depositRoot
    );

    /// @notice Emitted on a successful claim on the destination chain
    /// @param claimer Address that executed the claim
    /// @param amount Amount claimed
    /// @param token Token address (zero for native ETH)
    /// @param recipient Recipient of the assets
    /// @param sourceChain Source chain ID for the original deposit
    /// @param depositIndex Source deposit index
    /// @param claimIndex Assigned claim index on this chain
    /// @param sourceRoot Source deposit tree root used for verification
    /// @param claimRoot New claim tree root after insertion
    event Claimed(
        address indexed claimer,
        uint256 indexed amount,
        address indexed token,
        address recipient,
        uint256 sourceChain,
        uint256 depositIndex,
        uint256 claimIndex,
        bytes32 sourceRoot,
        bytes32 claimRoot
    );

    /// @notice Emitted when the validator manager address is updated
    /// @param currentManager Previous validator manager
    /// @param newManager New validator manager
    event ValidatorManagerUpdated(address indexed currentManager, address indexed newManager);

    /// @notice Invalid transaction parameters
    error InvalidTransaction();

    /// @notice Bridge lacks approval to spend tokens
    /// @param token ERC20 token address
    /// @param amount Required amount
    error BridgeNotApproved(address token, uint256 amount);

    /// @notice Insufficient contract or user balance
    /// @param token Token address (zero for ETH)
    /// @param amount Missing amount
    error InsufficientBalance(address token, uint256 amount);

    /// @notice ETH rescue transfer failed
    error FailedToRescueEther();

    /// @notice Invalid chain ID
    error InvalidChainId();

    /// @notice Root is not verified/accepted for the given bridge
    /// @param root Sparse Merkle tree root
    error InvalidRoot(bytes32 root);

    /// @notice Claim transfer failed
    /// @param token Token address (zero for ETH)
    /// @param to Intended recipient
    /// @param amount Amount attempted
    error ClaimFailed(address token, address to, uint256 amount);

    /// @notice bytes32 argument is zero
    error ZeroBytes32();

    /// @notice Deposit already claimed
    /// @param sourceChain Source chain ID
    /// @param depositIndex Deposit index
    error AlreadyClaimed(uint256 sourceChain, uint256 depositIndex);

    /// @notice Invalid Merkle proof
    /// @param depositIndex Deposit index being claimed
    error InvalidMerkleProof(uint256 depositIndex);

    /// @notice Source root is not valid for the given chain
    /// @param sourceChain Source chain ID
    /// @param root Root that failed validation
    error InvalidSourceRoot(uint256 sourceChain, bytes32 root);

    /// @notice Attempted to bridge to the same chain
    /// @param chainId Destination chain ID
    error SameChainTransfer(uint256 chainId);

    /// @notice Caller is not the bridge
    /// @dev Used to protect internal storage modifiers
    error NotBridge();

    /// @notice Tree operation failed
    /// @param operation Operation name ("add", "update", "remove")
    error TreeOperationFailed(string operation);
}
