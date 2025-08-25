// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@solarity/solidity-lib/libs/data-structures/SparseMerkleTree.sol";
import "../../src/libs/LocalExitTreeLib.sol";
import {BridgeBaseTest, SparseMerkleTree} from "../base/BridgeBase.t.sol";

/// @dev Im am to lazy to split the revert tests to another file
/// Since they arent that many so we shall bundle them with the positive
/// Tests
contract LocalExitTreeLibTest is BridgeBaseTest {
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;
    using SparseMerkleTree for SparseMerkleTree.Bytes32SMT;

    function test_SimpleDeposit() public {
        vm.selectFork(FORKA_ID);
        uint256 depositIndex = 0;
        DepositParams memory params = DepositParams({
            amount: 1 ether,
            to: bob,
            destinationChain: CHAINB_ID,
            token: address(TOKEN_CHAINA)
        });
        bytes32 exitLeaf = LocalExitTreeLib.computeExitLeaf(params);
        treeA.addDeposit(depositIndex, exitLeaf);
        SparseMerkleTree.Proof memory proof = treeA.getProof(depositIndex);
        bool valid = LocalExitTreeLib.verifyProof(treeA, proof);
        assertTrue(valid);
        assertEq(proof.value, exitLeaf);
    }

    function test_SimpleDeposit_Duplicate() public {
        vm.selectFork(FORKA_ID);
        uint256 depositIndex = 0;
        DepositParams memory params = DepositParams({
            amount: 1 ether,
            to: bob,
            destinationChain: CHAINB_ID,
            token: address(TOKEN_CHAINA)
        });
        bytes32 exitLeaf = LocalExitTreeLib.computeExitLeaf(params);
        treeA.addDeposit(depositIndex, exitLeaf);
        vm.expectRevert(
            abi.encodeWithSelector(
                SparseMerkleTree.KeyAlreadyExists.selector, bytes32(depositIndex)
            )
        );
        treeA.addDeposit(depositIndex, exitLeaf);
    }

    function test_BatchDeposits() public {
        vm.selectFork(FORKA_ID);
        uint256 startIndex = 10;
        uint256 batchSize = 5;
        bytes32[] memory exitLeaves = new bytes32[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            DepositParams memory params = DepositParams({
                amount: (i + 1) * 0.5 ether,
                to: bob,
                destinationChain: CHAINB_ID,
                token: address(TOKEN_CHAINA)
            });
            exitLeaves[i] = LocalExitTreeLib.computeExitLeaf(params);
        }

        treeA.batchAddDeposits(startIndex, exitLeaves);

        for (uint256 i = 0; i < batchSize; i++) {
            vm.selectFork(FORKA_ID);
            SparseMerkleTree.Proof memory proof = treeA.getProof(startIndex + i);
            bool valid = LocalExitTreeLib.verifyProof(treeA, proof);
            assertTrue(valid);
            assertEq(proof.value, exitLeaves[i]);
        }
    }
}
