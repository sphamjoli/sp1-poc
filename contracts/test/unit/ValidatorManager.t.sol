// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IValidatorTypes} from "../../src/validator/IValidatorManager.sol";
import {ValidatorManagerBaseTest} from "../base/ValidatorManagerBase.t.sol";
import {IStakeManagerTypes} from "../../src/stake/IStakeManagerTypes.sol";

contract ValidatorManagerTest is ValidatorManagerBaseTest {
    address[] internal validatorAddresses;

    function setUp() public virtual override {
        super.setUp();
        validatorAddresses = [alice, bob, spha, james, jenifer];
    }

    function test_validAttestationFlow_fromBaseToSatellite() public {
        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            _stakeAsUser(validatorAddresses[index], 200 ether, FORKA_ID);
            _addValidatorToManager(validatorAddresses[index], FORKB_ID);
        }

        bytes32 baseBridgeRoot = _generateBridgeMockRoot(1);

        vm.selectFork(FORKB_ID);
        uint256 attestationBlockNumber = 1000;
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            (bytes memory certificate,) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);

            IValidatorTypes.BridgeAttestation memory attestation = _createAttestation(
                validatorAddresses[index],
                baseBridgeRoot,
                attestationBlockNumber,
                certificate,
                block.chainid
            );

            attestation.signature = _signAttestation(validatorAddresses[index], block.chainid);
            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestation);

            if (index >= 3) {
                IValidatorTypes.RootParams memory rootParams = IValidatorTypes.RootParams({
                    chainId: block.chainid,
                    bridgeRoot: baseBridgeRoot,
                    blockNumber: attestationBlockNumber,
                    stateRoot: attestation.stateRoot
                });

                assertTrue(validatorManagerB.isRootVerified(rootParams));
            }
        }

        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            vm.selectFork(FORKA_ID);
            IValidatorTypes.ValidatorInfo memory validatorInfoA =
                validatorManagerA.getValidator(validatorAddresses[index]);
            vm.selectFork(FORKB_ID);
            IValidatorTypes.ValidatorInfo memory validatorInfoB =
                validatorManagerB.getValidator(validatorAddresses[index]);

            assertEq(
                uint256(validatorInfoA.status), uint256(IValidatorTypes.ValidatorStatus.Active)
            );
            assertEq(
                uint256(validatorInfoB.status), uint256(IValidatorTypes.ValidatorStatus.Active)
            );
        }
    }

    function test_certificateExpiry_preventsLateAttestation() public {
        vm.selectFork(FORKA_ID);
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _addValidatorToManager(alice, FORKB_ID);

        bytes32 baseBridgeRoot = _generateBridgeMockRoot(2);

        vm.selectFork(FORKB_ID);

        uint256 issuedAtTimestamp = block.timestamp;
        uint256 certificateExpiryTimestamp = issuedAtTimestamp + 600;

        (bytes memory certificateBytes,) =
            _issueCertificate(alice, FORKB_ID, certificateExpiryTimestamp);

        vm.warp(issuedAtTimestamp + 300);
        {
            IValidatorTypes.BridgeAttestation memory attestationEarly =
                _createAttestation(alice, baseBridgeRoot, 3000, certificateBytes, block.chainid);
            attestationEarly.signature = _signAttestation(alice, block.chainid);

            vm.prank(alice);
            validatorManagerB.submitAttestation(attestationEarly);
        }

        vm.warp(issuedAtTimestamp + 700);
        {
            IValidatorTypes.BridgeAttestation memory attestationLate =
                _createAttestation(alice, baseBridgeRoot, 3100, certificateBytes, block.chainid);
            attestationLate.signature = _signAttestation(alice, block.chainid);

            uint256 currentTimestampAtRevert = block.timestamp;

            vm.prank(alice);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IValidatorTypes.CertificateExpired.selector,
                    currentTimestampAtRevert,
                    certificateExpiryTimestamp
                )
            );
            validatorManagerB.submitAttestation(attestationLate);
        }
    }

    function test_certificateBinding_preventsCertificateReuse() public {
        vm.selectFork(FORKA_ID);
        _stakeAsUser(bob, 200 ether, FORKA_ID);
        _addValidatorToManager(bob, FORKB_ID);

        bytes32 baseBridgeRoot = _generateBridgeMockRoot(3);

        vm.selectFork(FORKB_ID);
        (bytes memory certificateForChainB,) = _issueCertificate(bob, FORKB_ID, 0);

        IValidatorTypes.BridgeAttestation memory attestationOnChainB =
            _createAttestation(bob, baseBridgeRoot, 4000, certificateForChainB, block.chainid);
        attestationOnChainB.signature = _signAttestation(bob, block.chainid);
        vm.prank(bob);
        validatorManagerB.submitAttestation(attestationOnChainB);

        vm.selectFork(FORKA_ID);
        IValidatorTypes.BridgeAttestation memory attestationOnChainAInvalid =
            _createAttestation(bob, baseBridgeRoot, 4100, certificateForChainB, block.chainid);
        attestationOnChainAInvalid.signature = _signAttestation(bob, block.chainid);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IValidatorTypes.InvalidCertificateSigner.selector,
                address(0x5ae41Ab84725d228658EEd1d5f367B9CDc01e876),
                address(0x2FF81E7B4C2C8daDAb51A1f2B451b4FCcb7a3dB0)
            )
        );
        validatorManagerA.submitAttestation(attestationOnChainAInvalid);

        (bytes memory certificateForChainA,) = _issueCertificate(bob, FORKA_ID, 0);
        IValidatorTypes.BridgeAttestation memory attestationOnChainAValid =
            _createAttestation(bob, baseBridgeRoot, 4200, certificateForChainA, block.chainid);
        attestationOnChainAValid.signature = _signAttestation(bob, block.chainid);
        vm.prank(bob);
        validatorManagerA.submitAttestation(attestationOnChainAValid);
    }

    function test_quorumThreshold_onSatelliteChain() public {
        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            _stakeAsUser(validatorAddresses[index], 200 ether, FORKA_ID);
            _addValidatorToManager(validatorAddresses[index], FORKB_ID);
        }

        bytes32 bridgeRoot = _generateBridgeMockRoot(4);

        vm.selectFork(FORKB_ID);
        bytes[] memory certificates = new bytes[](validatorAddresses.length);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            (certificates[index],) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);
        }

        uint256 attestationBlockNumber = 6000;

        for (uint256 index = 0; index < 3; index++) {
            IValidatorTypes.BridgeAttestation memory attestation = _createAttestation(
                validatorAddresses[index],
                bridgeRoot,
                attestationBlockNumber,
                certificates[index],
                block.chainid
            );
            attestation.signature = _signAttestation(validatorAddresses[index], block.chainid);

            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestation);

            IValidatorTypes.RootParams memory rootParameters = IValidatorTypes.RootParams({
                chainId: FORKA_ID,
                bridgeRoot: bridgeRoot,
                blockNumber: attestationBlockNumber,
                stateRoot: attestation.stateRoot
            });
            assertFalse(validatorManagerB.isRootVerified(rootParameters));
        }

        {
            IValidatorTypes.BridgeAttestation memory attestationForFourthValidator =
            _createAttestation(
                validatorAddresses[3],
                bridgeRoot,
                attestationBlockNumber,
                certificates[3],
                block.chainid
            );
            attestationForFourthValidator.signature =
                _signAttestation(validatorAddresses[3], block.chainid);

            vm.prank(validatorAddresses[3]);
            validatorManagerB.submitAttestation(attestationForFourthValidator);

            IValidatorTypes.RootParams memory rootParameters = IValidatorTypes.RootParams({
                chainId: block.chainid,
                bridgeRoot: bridgeRoot,
                blockNumber: attestationBlockNumber,
                stateRoot: attestationForFourthValidator.stateRoot
            });
            assertTrue(validatorManagerB.isRootVerified(rootParameters));
        }

        {
            bytes32 otherBridgeRoot = _generateBridgeMockRoot(5);
            IValidatorTypes.BridgeAttestation memory attestationForFifthValidator =
            _createAttestation(
                validatorAddresses[4], otherBridgeRoot, 8000, certificates[4], block.chainid
            );
            attestationForFifthValidator.signature =
                _signAttestation(validatorAddresses[4], block.chainid);

            vm.prank(validatorAddresses[4]);
            validatorManagerB.submitAttestation(attestationForFifthValidator);

            IValidatorTypes.RootParams memory otherRootParameters = IValidatorTypes.RootParams({
                chainId: block.chainid,
                bridgeRoot: otherBridgeRoot,
                blockNumber: 8000,
                stateRoot: attestationForFifthValidator.stateRoot
            });
            assertFalse(validatorManagerB.isRootVerified(otherRootParameters));
        }
    }

    function test_duplicateAttestation_isRejected() public {
        address validatorAddress = spha;

        vm.selectFork(FORKA_ID);
        _stakeAsUser(validatorAddress, 200 ether, FORKA_ID);
        _addValidatorToManager(validatorAddress, FORKB_ID);

        bytes32 bridgeRootSix = _generateBridgeMockRoot(6);

        vm.selectFork(FORKB_ID);
        (bytes memory certificate,) = _issueCertificate(validatorAddress, FORKB_ID, 0);

        {
            IValidatorTypes.BridgeAttestation memory firstAttestation = _createAttestation(
                validatorAddress, bridgeRootSix, 9000, certificate, block.chainid
            );
            firstAttestation.signature = _signAttestation(validatorAddress, block.chainid);
            vm.prank(validatorAddress);
            validatorManagerB.submitAttestation(firstAttestation);
        }

        {
            IValidatorTypes.BridgeAttestation memory duplicateAttestation = _createAttestation(
                validatorAddress, bridgeRootSix, 9000, certificate, block.chainid
            );
            duplicateAttestation.signature = _signAttestation(validatorAddress, block.chainid);
            vm.prank(validatorAddress);
            vm.expectRevert(IValidatorTypes.AlreadyAttested.selector);
            validatorManagerB.submitAttestation(duplicateAttestation);
        }
    }

    function test_Finalization() public {
        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            _stakeAsUser(validatorAddresses[index], 200 ether, FORKA_ID);
            vm.selectFork(FORKB_ID);
            _addValidatorToManager(validatorAddresses[index], FORKB_ID);
        }

        bytes32 root = _generateBridgeMockRoot(1);
        IValidatorTypes.BridgeAttestation[] memory attestations =
            new IValidatorTypes.BridgeAttestation[](5);
        bytes32 bridgeRoot = _generateBridgeMockRoot(8);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            (bytes memory certificate,) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);

            attestations[index] = _createAttestation(
                validatorAddresses[index], bridgeRoot, 10000, certificate, block.chainid
            );
            vm.selectFork(FORKB_ID);
            vm.startPrank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations[index]);
        }
        IStakeManagerTypes.SlashParams[] memory equivocators =
            _createEquivicators(validatorAddresses, validatorAddresses.length, 0);

        _finalizeWithMocks(attestations, equivocators, root, FORKA_ID);

        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            assertEq(validatorManagerA.getValidator(validatorAddresses[index]).attestationCount, 1);
        }
    }

    function test_FinalizeWithEquivicators() public {
        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            _stakeAsUser(validatorAddresses[index], 200 ether, FORKA_ID);
            vm.selectFork(FORKB_ID);
            _addValidatorToManager(validatorAddresses[index], FORKB_ID);
        }

        bytes32 root = _generateBridgeMockRoot(1);
        IValidatorTypes.BridgeAttestation[] memory attestations =
            new IValidatorTypes.BridgeAttestation[](5);
        bytes32 bridgeRoot = _generateBridgeMockRoot(8);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            (bytes memory certificate,) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);

            attestations[index] = _createAttestation(
                validatorAddresses[index], bridgeRoot, 10000, certificate, block.chainid
            );
            vm.selectFork(FORKB_ID);
            vm.startPrank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations[index]);
        }

        vm.selectFork(FORKA_ID);
        (uint256 minStakeAmount,,,,,,,) = stakeManagerA.ACTIVE_STAKING_CONFIG();

        uint256 slashAmount = minStakeAmount - 1;
        uint256 startIndex = 3;
        IStakeManagerTypes.SlashParams[] memory equivocators =
            _createEquivicators(validatorAddresses, startIndex, slashAmount);

        _finalizeWithMocks(attestations, equivocators, root, FORKA_ID);
        validatorManagerA.distributeRewards();

        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < startIndex; index++) {
            assertEq(validatorManagerA.getValidator(validatorAddresses[index]).attestationCount, 1);
        }

        for (uint256 index = startIndex + 1; index < validatorAddresses.length; index++) {
            assertEq(
                validatorManagerA.getValidator(validatorAddresses[index]).invalidAttestations, 1
            );
        }
    }

    function test_FinalizeWithJailedEquivicator_AndRecover() public {
        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            _stakeAsUser(validatorAddresses[index], 200 ether, FORKA_ID);
            vm.selectFork(FORKB_ID);
            _addValidatorToManager(validatorAddresses[index], FORKB_ID);
        }

        bytes32 root = _generateBridgeMockRoot(1);
        IValidatorTypes.BridgeAttestation[] memory attestations =
            new IValidatorTypes.BridgeAttestation[](5);
        bytes32 bridgeRoot = _generateBridgeMockRoot(8);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            (bytes memory certificate,) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);

            attestations[index] = _createAttestation(
                validatorAddresses[index], bridgeRoot, 10000, certificate, block.chainid
            );
            vm.selectFork(FORKB_ID);
            vm.startPrank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations[index]);
        }

        vm.selectFork(FORKA_ID);
        (uint256 minStakeAmount,,,,,,,) = stakeManagerA.ACTIVE_STAKING_CONFIG();

        uint256 slashAmount = minStakeAmount + 1;
        uint256 startIndex = 3;
        IStakeManagerTypes.SlashParams[] memory equivocators =
            _createEquivicators(validatorAddresses, startIndex, slashAmount);

        _finalizeWithMocks(attestations, equivocators, root, FORKA_ID);
        validatorManagerA.distributeRewards();

        vm.selectFork(FORKA_ID);
        for (uint256 index = startIndex; index < validatorAddresses.length; index++) {
            IValidatorTypes.ValidatorInfo memory validator =
                validatorManagerA.getValidator(validatorAddresses[index]);
            assertEq(uint256(validator.status), uint256(IValidatorTypes.ValidatorStatus.Inactive));
            _stakeAsUser(validator.wallet, minStakeAmount, FORKA_ID);
            validator = validatorManagerA.getValidator(validatorAddresses[index]);
            assertEq(uint256(validator.status), uint256(IValidatorTypes.ValidatorStatus.Active));
        }
    }

    function test_JailedValidator_NoRewards_UntilRecoveryy() public {
        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            _stakeAsUser(validatorAddresses[index], 200 ether, FORKA_ID);
            vm.selectFork(FORKB_ID);
            _addValidatorToManager(validatorAddresses[index], FORKB_ID);
        }

        vm.selectFork(FORKB_ID);
        bytes32 root1 = _generateBridgeMockRoot(1);
        bytes32 bridgeRoot1 = _generateBridgeMockRoot(8);
        IValidatorTypes.BridgeAttestation[] memory attestations1 =
            new IValidatorTypes.BridgeAttestation[](5);

        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            (bytes memory certificate,) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);
            attestations1[index] = _createAttestation(
                validatorAddresses[index], bridgeRoot1, 10000, certificate, block.chainid
            );
            vm.startPrank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations1[index]);
            vm.stopPrank();
        }

        vm.selectFork(FORKA_ID);
        (uint256 minStakeAmount,,,,,,,) = stakeManagerA.ACTIVE_STAKING_CONFIG();
        uint256 slashAmount = minStakeAmount + 1;
        uint256 jailedStartIndex = 3;
        IStakeManagerTypes.SlashParams[] memory equivocators =
            _createEquivicators(validatorAddresses, jailedStartIndex, slashAmount);

        _finalizeWithMocks(attestations1, equivocators, root1, FORKA_ID);

        for (uint256 i = jailedStartIndex; i < validatorAddresses.length; i++) {
            IValidatorTypes.ValidatorInfo memory validator =
                validatorManagerA.getValidator(validatorAddresses[i]);
            assertEq(uint256(validator.status), uint256(IValidatorTypes.ValidatorStatus.Inactive));
        }

        vm.selectFork(FORKA_ID);
        validatorManagerA.distributeRewards();

        for (uint256 i = jailedStartIndex; i < validatorAddresses.length; i++) {
            IValidatorTypes.ValidatorInfo memory validator =
                validatorManagerA.getValidator(validatorAddresses[i]);
            assertEq(validator.attestationCount, 0, "Jailed validator should have 0 attestations");
        }

        vm.warp(block.timestamp + validatorManagerA.EPOCH_DURATION());
        vm.selectFork(FORKB_ID);

        bytes32 root2 = _generateBridgeMockRoot(2);
        bytes32 bridgeRoot2 = _generateBridgeMockRoot(9);
        IValidatorTypes.BridgeAttestation[] memory attestations2 =
            new IValidatorTypes.BridgeAttestation[](3);

        for (uint256 index = 0; index < jailedStartIndex; index++) {
            (bytes memory certificate,) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);
            attestations2[index] = _createAttestation(
                validatorAddresses[index], bridgeRoot2, 10001, certificate, block.chainid
            );
            vm.startPrank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations2[index]);
            vm.stopPrank();
        }

        vm.selectFork(FORKA_ID);
        IStakeManagerTypes.SlashParams[] memory noEquivocators =
            new IStakeManagerTypes.SlashParams[](0);
        _finalizeWithMocks(attestations2, noEquivocators, root2, FORKA_ID);

        validatorManagerA.distributeRewards();

        for (uint256 i = jailedStartIndex; i < validatorAddresses.length; i++) {
            IValidatorTypes.ValidatorInfo memory validator =
                validatorManagerA.getValidator(validatorAddresses[i]);
            assertEq(validator.attestationCount, 0, "Jailed validator still at 0 after epoch 2");
        }

        vm.selectFork(FORKA_ID);
        for (uint256 i = jailedStartIndex; i < validatorAddresses.length; i++) {
            _stakeAsUser(validatorAddresses[i], minStakeAmount, FORKA_ID);
            IValidatorTypes.ValidatorInfo memory validator =
                validatorManagerA.getValidator(validatorAddresses[i]);
            assertEq(
                uint256(validator.status),
                uint256(IValidatorTypes.ValidatorStatus.Active),
                "Validator should be Active after top-up"
            );
        }

        vm.warp(block.timestamp + validatorManagerA.EPOCH_DURATION());
        vm.selectFork(FORKB_ID);

        bytes32 root3 = _generateBridgeMockRoot(3);
        bytes32 bridgeRoot3 = _generateBridgeMockRoot(10);
        IValidatorTypes.BridgeAttestation[] memory attestations3 =
            new IValidatorTypes.BridgeAttestation[](5);

        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            (bytes memory certificate,) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);
            attestations3[index] = _createAttestation(
                validatorAddresses[index], bridgeRoot3, 10002, certificate, block.chainid
            );
            vm.startPrank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations3[index]);
            vm.stopPrank();
        }

        vm.selectFork(FORKA_ID);
        _finalizeWithMocks(attestations3, noEquivocators, root3, FORKA_ID);

        validatorManagerA.distributeRewards();

        for (uint256 i = jailedStartIndex; i < validatorAddresses.length; i++) {
            IValidatorTypes.ValidatorInfo memory validator =
                validatorManagerA.getValidator(validatorAddresses[i]);
            assertEq(validator.attestationCount, 1, "Recovered validator should have 1 attestation");
        }

        for (uint256 i = 0; i < jailedStartIndex; i++) {
            IValidatorTypes.ValidatorInfo memory validator =
                validatorManagerA.getValidator(validatorAddresses[i]);
            assertEq(
                validator.attestationCount, 3, "Always-active validator should have 3 attestations"
            );
        }
    }
}
