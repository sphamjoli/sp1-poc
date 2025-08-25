// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@solarity/solidity-lib/libs/data-structures/SparseMerkleTree.sol";
import {IBridgeUtils} from "../bridge/IBridgeTypes.sol";

/// @title LocalExitTreeLib
/// @author brianspha
/// @notice Library for Sparse Merkle Tree operations in the bridge system
/// @dev This is purely for educational purposes
library LocalExitTreeLib {
    using SparseMerkleTree for SparseMerkleTree.Bytes32SMT;
    using SparseMerkleTree for SparseMerkleTree.Proof;

    /// @notice we KEEP the max HEIGHT for the tree at 32
    /// This enabled 2^32 possible leaves which is enough
    /// For our POC
    uint32 public constant TREE_HEIGHT = 32;

    /// @notice Initialize a new SMT
    /// @param tree The SMT storage reference
    /// @dev Initializes with 32 height
    function initialize(SparseMerkleTree.Bytes32SMT storage tree) internal {
        tree.initialize(TREE_HEIGHT);
    }

    /// @notice Add a deposit leaf to the tree
    /// @param tree The SMT storage reference
    /// @param depositIndex The deposit index (used as key)
    /// @param exitLeaf The exit leaf hash (used as value)
    /// @return newRoot The new root after insertion
    function addDeposit(
        SparseMerkleTree.Bytes32SMT storage tree,
        uint256 depositIndex,
        bytes32 exitLeaf
    )
        internal
        returns (bytes32 newRoot)
    {
        bytes32 key = bytes32(depositIndex);
        tree.add(key, exitLeaf);
        return tree.getRoot();
    }

    /// @notice Batch add multiple deposits
    /// @param tree The SMT storage reference
    /// @param startIndex Starting deposit index ideally the deposit/claim count
    /// @param exitLeaves Array of exit leaves to add
    /// @return newRoot The new root after all insertions
    function batchAddDeposits(
        SparseMerkleTree.Bytes32SMT storage tree,
        uint256 startIndex,
        bytes32[] memory exitLeaves
    )
        internal
        returns (bytes32 newRoot)
    {
        for (uint256 i = 0; i < exitLeaves.length; i++) {
            bytes32 key = bytes32(startIndex + i);
            tree.add(key, exitLeaves[i]);
        }
        return tree.getRoot();
    }

    /// @notice Generate a proof for a deposit
    /// @param tree The SMT storage reference
    /// @param depositIndex The deposit index
    /// @return proof The generated proof
    function getProof(
        SparseMerkleTree.Bytes32SMT storage tree,
        uint256 depositIndex
    )
        internal
        view
        returns (SparseMerkleTree.Proof memory proof)
    {
        bytes32 key = bytes32(depositIndex);
        return tree.getProof(key);
    }

    /// @notice Verify a proof against a root
    /// @param tree The current active tree
    /// @param proof The proof to verify
    /// @return valid Whether the proof is valid
    function verifyProof(
        SparseMerkleTree.Bytes32SMT storage tree,
        SparseMerkleTree.Proof memory proof
    )
        internal
        view
        returns (bool valid)
    {
        return tree.verifyProof(proof);
    }

    /// @notice Compute exit leaf hash using DepositParams
    /// @dev see {IBridgeUtils.DepositParams}
    /// @return exitLeaf The computed exit leaf
    function computeExitLeaf(IBridgeUtils.DepositParams memory params)
        internal
        pure
        returns (bytes32 exitLeaf)
    {
        return
            keccak256(abi.encode(params.amount, params.token, params.to, params.destinationChain));
    }

    /// @notice Check if a leaf exists in the tree
    /// @param tree The SMT storage reference
    /// @param depositIndex The deposit index to check
    /// @return exists Whether the leaf exists
    /// @return value The leaf value if it exists
    function checkLeafExists(
        SparseMerkleTree.Bytes32SMT storage tree,
        uint256 depositIndex
    )
        internal
        view
        returns (bool exists, bytes32 value)
    {
        bytes32 key = bytes32(depositIndex);
        SparseMerkleTree.Node memory node = tree.getNodeByKey(key);

        exists = node.value != bytes32(0);
        value = node.value;

        return (exists, value);
    }

    /// @notice Get the current root of the tree
    /// @param tree The SMT storage reference
    /// @return root The current root
    function getRoot(SparseMerkleTree.Bytes32SMT storage tree)
        internal
        view
        returns (bytes32 root)
    {
        return tree.getRoot();
    }

    /// @notice Check if tree is initialized checks if the tree has any nodes
    /// @param tree The SMT storage reference
    /// @return initialized Whether the tree is initialized
    function isInitialized(SparseMerkleTree.Bytes32SMT storage tree)
        internal
        view
        returns (bool initialized)
    {
        return tree.getNodesCount() > 0;
    }

    /// @notice Remove a leaf from the tree (for rollback scenarios)
    /// @param tree The SMT storage reference
    /// @param depositIndex The deposit index to remove
    /// @return newRoot The new root after removal
    function removeDeposit(
        SparseMerkleTree.Bytes32SMT storage tree,
        uint256 depositIndex
    )
        internal
        returns (bytes32 newRoot)
    {
        bytes32 key = bytes32(depositIndex);
        tree.remove(key);
        return tree.getRoot();
    }

    /// @notice Update an existing leaf value
    /// @param tree The SMT storage reference
    /// @param depositIndex The deposit index to update
    /// @param newExitLeaf The new exit leaf value
    /// @return newRoot The new root after update
    function updateDeposit(
        SparseMerkleTree.Bytes32SMT storage tree,
        uint256 depositIndex,
        bytes32 newExitLeaf
    )
        internal
        returns (bytes32 newRoot)
    {
        bytes32 key = bytes32(depositIndex);
        tree.update(key, newExitLeaf);
        return tree.getRoot();
    }
}
