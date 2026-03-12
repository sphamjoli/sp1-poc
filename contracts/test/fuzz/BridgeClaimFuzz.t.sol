// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeBaseTest} from "../base/BridgeBase.t.sol";
import {IValidatorTypes} from "../../src/validator/IValidatorTypes.sol";
import {LocalExitTreeLib, SparseMerkleTree} from "../../src/libs/LocalExitTreeLib.sol";

contract FuzzMockValidatorManager {
    function isRootVerified(IValidatorTypes.RootParams calldata) external pure returns (bool) {
        return true;
    }
}

contract BridgeClaimFuzzTest is BridgeBaseTest {
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;

    function testFuzz_ClaimReplayRejected(uint96 rawAmount, uint64 rawIndex) public {
        uint256 amount = bound(uint256(rawAmount), 1, 100 ether);
        uint256 depositIndex = bound(uint256(rawIndex), 0, type(uint32).max);

        vm.selectFork(FORKA_ID);
        DepositParams memory originalDeposit = DepositParams({
            amount: amount,
            token: address(TOKEN_CHAINB),
            to: alice,
            destinationChain: CHAINB_ID
        });

        bytes32 leaf = LocalExitTreeLib.computeExitLeaf(originalDeposit, CHAINA_ID, depositIndex);
        treeA.addDeposit(depositIndex, leaf);
        SparseMerkleTree.Proof memory proof = treeA.getProof(depositIndex);

        vm.selectFork(FORKB_ID);
        FuzzMockValidatorManager mockValidator = new FuzzMockValidatorManager();

        vm.prank(ownerB);
        CHAINB.updateValidatorManager(address(mockValidator));

        vm.prank(ownerB);
        TOKEN_CHAINB.transfer(address(CHAINB), amount);

        ClaimParams memory claimParams = ClaimParams({
            depositIndex: depositIndex,
            sourceChain: uint32(CHAINA_ID),
            token: address(TOKEN_CHAINB),
            to: alice,
            amount: amount,
            sourceRoot: treeA.getRoot(),
            blockNumber: 1,
            stateRoot: bytes32(uint256(1)),
            proof: proof
        });

        vm.prank(alice);
        CHAINB.claim(claimParams);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                AlreadyClaimed.selector, uint256(claimParams.sourceChain), claimParams.depositIndex
            )
        );
        CHAINB.claim(claimParams);
    }
}
