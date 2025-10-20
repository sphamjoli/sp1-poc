// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakeManagerBaseTest} from "../base/StakeManagerBase.t.sol";
import {IValidatorTypes} from "../../src/validator/IValidatorTypes.sol";

contract StakeManagerFuzzTest is StakeManagerBaseTest {
    ///@dev I need to add more fuzz tests here
    function testFuzz_ClaimRewards_RevertsWhenUnfunded(uint256 stakeAmt) public {
        vm.selectFork(FORKA_ID);
        uint256 amnt = TOKEN_CHAINA.balanceOf(alice);
        vm.assume(stakeAmt >= testConfigA.minStakeAmount && stakeAmt < type(uint256).max - amnt);

        if (stakeAmt > amnt) {
            _prankOwnerOnChain(FORKA_ID);
            TOKEN_CHAINA.mint(alice, stakeAmt - amnt);
            vm.stopPrank();
        }

        _stakeAsUser(alice, stakeAmt, FORKA_ID);
        _distributeRewardsToValidator(alice, FORKA_ID, 1);

        vm.prank(alice);
        vm.expectRevert();
        stakeManagerA.claimRewards();
    }

    function testFuzz_DistributeRewards_IssuesUnclaimableBalance(uint256 stakeAmt) public {
        vm.selectFork(FORKA_ID);
        uint256 amnt = TOKEN_CHAINA.balanceOf(alice);
        vm.assume(stakeAmt >= testConfigA.minStakeAmount && stakeAmt < type(uint256).max - amnt);

        if (stakeAmt > amnt) {
            _prankOwnerOnChain(FORKA_ID);
            TOKEN_CHAINA.mint(alice, stakeAmt - amnt);
            vm.stopPrank();
        }

        _stakeAsUser(alice, stakeAmt, FORKA_ID);
        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](1);

        BlsTestData memory a = validatorBlsData[alice];
        IValidatorTypes.ValidatorInfo;
        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(a.publicKey[0]),
                vm.parseUint(a.publicKey[1]),
                vm.parseUint(a.publicKey[2]),
                vm.parseUint(a.publicKey[3])
            ],
            wallet: alice,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 100,
            invalidAttestations: 0
        });

        vm.prank(address(validatorManagerA));
        stakeManagerA.distributeRewards(
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600})
        );

        uint256 accrued = stakeManagerA.getLatestRewards(alice);
        assertTrue(accrued > 0);

        vm.prank(alice);
        vm.expectRevert();
        stakeManagerA.claimRewards();
    }
}
