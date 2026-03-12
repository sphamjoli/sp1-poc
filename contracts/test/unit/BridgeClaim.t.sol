// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeBaseTest} from "../base/BridgeBase.t.sol";
import {IValidatorTypes} from "../../src/validator/IValidatorTypes.sol";
import {LocalExitTreeLib, SparseMerkleTree} from "../../src/libs/LocalExitTreeLib.sol";

contract MockValidatorManager {
    bool internal verified = true;

    function setVerified(bool isVerified) external {
        verified = isVerified;
    }

    function isRootVerified(IValidatorTypes.RootParams calldata) external view returns (bool) {
        return verified;
    }
}

contract BridgeClaimTest is BridgeBaseTest {
    using LocalExitTreeLib for SparseMerkleTree.Bytes32SMT;

    function _prepareClaim(
        uint256 amount,
        uint256 depositIndex
    )
        internal
        returns (ClaimParams memory claimParams, MockValidatorManager mockValidator)
    {
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
        bytes32 sourceRoot = treeA.getRoot();

        vm.selectFork(FORKB_ID);
        mockValidator = new MockValidatorManager();

        vm.prank(ownerB);
        CHAINB.updateValidatorManager(address(mockValidator));

        vm.prank(ownerB);
        TOKEN_CHAINB.transfer(address(CHAINB), amount);

        claimParams = ClaimParams({
            depositIndex: depositIndex,
            sourceChain: uint32(CHAINA_ID),
            token: address(TOKEN_CHAINB),
            to: alice,
            amount: amount,
            sourceRoot: sourceRoot,
            blockNumber: 1,
            stateRoot: bytes32(uint256(1)),
            proof: proof
        });
    }

    function test_claimSuccess_TransfersTokensAndMarksClaimed() public {
        (ClaimParams memory claimParams,) = _prepareClaim(2 ether, 0);

        vm.selectFork(FORKB_ID);
        uint256 before = TOKEN_CHAINB.balanceOf(alice);

        vm.prank(alice);
        CHAINB.claim(claimParams);

        assertEq(TOKEN_CHAINB.balanceOf(alice), before + claimParams.amount);
        assertEq(CHAINB.CLAIM_COUNTER(), 1);
    }

    function test_claimRevertsWhenRootNotVerified() public {
        (ClaimParams memory claimParams, MockValidatorManager mockValidator) =
            _prepareClaim(1 ether, 0);

        vm.selectFork(FORKB_ID);
        mockValidator.setVerified(false);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidRoot.selector, claimParams.sourceRoot));
        CHAINB.claim(claimParams);
    }

    function test_claimRevertsOnInvalidProof() public {
        (ClaimParams memory claimParams,) = _prepareClaim(1 ether, 0);

        vm.selectFork(FORKB_ID);
        claimParams.proof.value = bytes32(uint256(claimParams.proof.value) + 1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidMerkleProof.selector, claimParams.depositIndex)
        );
        CHAINB.claim(claimParams);
    }

    function test_claimRevertsOnReplay() public {
        (ClaimParams memory claimParams,) = _prepareClaim(1 ether, 0);

        vm.selectFork(FORKB_ID);
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

    function test_claimRevertsWhenCallerNotRecipient() public {
        (ClaimParams memory claimParams,) = _prepareClaim(1 ether, 0);

        vm.selectFork(FORKB_ID);
        vm.prank(bob);
        vm.expectRevert(InvalidTransaction.selector);
        CHAINB.claim(claimParams);
    }
}
