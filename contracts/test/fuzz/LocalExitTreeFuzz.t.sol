// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SparseMerkleTree} from "@solarity/solidity-lib/libs/data-structures/SparseMerkleTree.sol";
import {LocalExitTreeLib} from "../../src/libs/LocalExitTreeLib.sol";
import {BridgeBaseTest, SparseMerkleTree} from "../base/BridgeBase.t.sol";

contract LocalExitTreeLibFuzzTest is BridgeBaseTest {
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;
    using SparseMerkleTree for SparseMerkleTree.Bytes32SMT;

    function testFuzz_SimpleDeposit(
        uint256 depositIndex,
        uint256 amount,
        address to,
        address token
    )
        public
    {
        vm.selectFork(FORKA_ID);

        depositIndex = bound(depositIndex, 0, type(uint64).max);
        amount = bound(amount, 1, 1e36);
        vm.assume(to != address(0));
        vm.assume(token != address(0));

        DepositParams memory params =
            DepositParams({amount: amount, to: to, destinationChain: CHAINB_ID, token: token});

        bytes32 exitLeaf = LocalExitTreeLib.computeExitLeaf(params, block.chainid, depositIndex);
        treeA.addDeposit(depositIndex, exitLeaf);

        SparseMerkleTree.Proof memory proof = treeA.getProof(depositIndex);
        bool valid = LocalExitTreeLib.verifyProof(treeA, proof);
        assertTrue(valid);
        assertEq(proof.value, exitLeaf);
    }

    function testFuzz_SimpleDeposit_Duplicate(
        uint256 depositIndex,
        uint256 amount,
        address to,
        address token
    )
        public
    {
        vm.selectFork(FORKA_ID);

        depositIndex = bound(depositIndex, 0, type(uint64).max);
        amount = bound(amount, 1, 1e36);
        vm.assume(to != address(0));
        vm.assume(token != address(0));

        DepositParams memory params =
            DepositParams({amount: amount, to: to, destinationChain: CHAINB_ID, token: token});

        bytes32 exitLeaf = LocalExitTreeLib.computeExitLeaf(params, block.chainid, depositIndex);
        treeA.addDeposit(depositIndex, exitLeaf);

        vm.expectRevert(
            abi.encodeWithSelector(
                SparseMerkleTree.KeyAlreadyExists.selector, bytes32(depositIndex)
            )
        );
        treeA.addDeposit(depositIndex, exitLeaf);
    }

    function testFuzz_BatchDeposits(uint256 startIndex, uint8 batchSizeSeed, bytes32 seed) public {
        vm.selectFork(FORKA_ID);

        uint256 batchSize = bound(uint256(batchSizeSeed), 1, 25);
        startIndex = bound(startIndex, 0, type(uint64).max - batchSize);

        bytes32[] memory exitLeaves = new bytes32[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            bytes32 h = keccak256(abi.encode(seed, i));
            uint256 amount = (uint256(h) % 10_000 ether) + 1;
            address to = address(uint160(uint256(keccak256(abi.encode(h, "to")))));
            if (to == address(0)) {
                to = bob;
            }
            address token = address(uint160(uint256(keccak256(abi.encode(h, "token")))));
            if (token == address(0)) {
                token = address(TOKEN_CHAINA);
            }

            DepositParams memory params =
                DepositParams({amount: amount, to: to, destinationChain: CHAINB_ID, token: token});

            exitLeaves[i] = LocalExitTreeLib.computeExitLeaf(params, block.chainid, i);
        }

        treeA.batchAddDeposits(startIndex, exitLeaves);

        for (uint256 i = 0; i < batchSize; i++) {
            SparseMerkleTree.Proof memory proof = treeA.getProof(startIndex + i);
            bool valid = LocalExitTreeLib.verifyProof(treeA, proof);
            assertTrue(valid);
            assertEq(proof.value, exitLeaves[i]);
        }
    }
}
