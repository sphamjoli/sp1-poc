// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SparseMerkleTree} from "../libs/LocalExitTreeLib.sol";

/// @title IBridgeUtils
/// @author brianspha
/// @notice Interface providing common events and errors for cross-chain bridge system
/// @dev Base interface inherited by all bridge contracts for consistent event emission and error handling
interface IBridgeUtils {
    /// @notice Bridge storage structure
    /// @dev Append-only structure for safe upgrades
    struct Storage {
        /// @dev Sparse merkle tree for tracking deposits
        SparseMerkleTree.Bytes32SMT depositTree;
        /// @dev Sparse merkle tree for tracking claims
        SparseMerkleTree.Bytes32SMT claimTree;
        /// @dev Counter for deposit indices
        uint256 depositCounter;
        /// @dev Counter for claim indices
        uint256 claimCounter;
        /// @dev Maps source chain ID => root hash => validity status
        mapping(uint256 => mapping(bytes32 => bool)) validRoots;
        /// @dev Maps (sourceChain, depositIndex) => claimed status
        mapping(bytes32 => bool) claimed;
        /// @dev Reserved slots for future upgrades
        uint256[50] __gap;
    }

    /// @notice Parameters for deposit operations
    /// @param amount Amount of assets to deposit
    /// @param token Token contract address (zero address for native ETH)
    /// @param to Recipient address on destination chain
    /// @param destinationChain Chain ID where assets will be claimed
    struct DepositParams {
        uint256 amount;
        address token;
        address to;
        uint256 destinationChain;
    }

    /// @notice Structure representing a claim leaf in the claim tree
    /// @param sourceDepositIndex Index of the original deposit in source chain
    /// @param sourceChain Chain ID where the original deposit was made
    /// @param sourceRoot Source chain tree root used for verification
    /// @param claimer Address that executed the claim transaction
    /// @param recipient Address that received the claimed assets
    /// @param amount Amount of assets claimed
    /// @param token Token contract address being claimed
    /// @param timestamp Block timestamp when claim was processed
    struct ClaimLeaf {
        uint256 sourceDepositIndex;
        uint256 sourceChain;
        bytes32 sourceRoot;
        address claimer;
        address recipient;
        uint256 amount;
        address token;
        uint256 timestamp;
    }

    /// @notice Parameters for claim operations
    /// @param depositIndex Index of the deposit in source chain tree
    /// @param originChain Source chain ID where deposit was made
    /// @param token Token contract address being claimed
    /// @param to Recipient address for the claimed assets
    /// @param amount Amount being claimed
    /// @param sourceRoot Source chain tree root to verify against
    /// @param proof Merkle inclusion proof from source chain tree
    struct ClaimParams {
        uint256 depositIndex;
        uint32 originChain;
        address token;
        address to;
        uint256 amount;
        bytes32 sourceRoot;
        SparseMerkleTree.Proof proof;
    }

    /// @notice Emitted when a user deposits assets to be bridged to another chain
    /// @param who The address of the user making the deposit
    /// @param amount The amount of assets deposited
    /// @param token The token contract address (zero address for native ETH)
    /// @param to The destination address on the target chain
    /// @param sourceChain The chain ID where the deposit was made
    /// @param destinationChain The chain ID where assets will be claimed
    /// @param depositIndex The index of this deposit in the source chain tree
    /// @param depositRoot The updated deposit tree root after this deposit
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

    /// @notice Emitted when a user successfully claims bridged assets on the destination chain
    /// @param claimer The address that executed the claim transaction
    /// @param amount The amount of assets claimed
    /// @param token The token contract address (zero address for native ETH)
    /// @param recipient The address that received the claimed assets
    /// @param sourceChain The chain ID where the original deposit occurred
    /// @param depositIndex The index of the original deposit in source chain
    /// @param claimIndex The index of this claim in the destination chain claim tree
    /// @param sourceRoot The source chain tree root used for verification
    /// @param claimRoot The updated claim tree root after this claim
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

    /// @notice Invalid transaction parameters provided
    error InvalidTransaction();

    /// @notice Bridge contract lacks approval to spend required token amount
    /// @param token ERC20 token contract address that lacks approval
    /// @param amount Amount that was attempted to be transferred
    error BridgeNotApproved(address token, uint256 amount);

    /// @notice Insufficient funds available for the requested operation
    /// @param token Token contract address (zero address for ETH)
    /// @param amount Amount that was requested but unavailable
    error InsufficientBalance(address token, uint256 amount);

    /// @notice Native ETH rescue operation failed
    error FailedToRescueEther();

    /// @notice Asset claim operation failed to complete successfully
    /// @param token Token contract address that failed to transfer (zero address for ETH)
    /// @param to Intended recipient address
    /// @param amount Amount that failed to transfer
    error ClaimFailed(address token, address to, uint256 amount);

    /// @notice Required bytes32 parameter is zero
    error ZeroBytes32();

    /// @notice Required address parameter is the zero address
    error ZeroAddress();

    /// @notice Deposit has already been claimed
    /// @param sourceChain Source chain ID
    /// @param depositIndex Index of the deposit that was already claimed
    error AlreadyClaimed(uint256 sourceChain, uint256 depositIndex);

    /// @notice Invalid merkle proof provided for claim verification
    /// @param depositIndex Index of the deposit being claimed
    error InvalidMerkleProof(uint256 depositIndex);

    /// @notice Source chain root is not valid or not verified
    /// @param sourceChain Chain ID of the source chain
    /// @param root Tree root that is not valid
    error InvalidSourceRoot(uint256 sourceChain, bytes32 root);

    /// @notice Attempting to bridge to the same chain as source
    /// @param chainId Invalid destination chain ID
    error SameChainTransfer(uint256 chainId);

    /// @notice Thrown when caller is not the bridge contract
    /// @dev Used to protect the bridge storage
    error NotBridge();

    /// @notice Tree operation failed
    /// @param operation The operation that failed (add, update, remove)
    error TreeOperationFailed(string operation);
}
