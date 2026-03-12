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

    function test_initializeSetsOwnerVerifierAndProgramKey() public {
        vm.selectFork(FORKA_ID);

        assertEq(validatorManagerA.owner(), ownerA);
        assertEq(validatorManagerA.SP1_VERIFIER(), SP1_VERIFIER);
        assertEq(validatorManagerA.PROGRAM_KEY(), PROGRAM_VKEY);
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
                CHAINA_ID
            );

            attestation.signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestation.blockNumber,
                attestation.bridgeRoot,
                attestation.stateRoot,
                attestation.timestamp
            );
            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestation);

            if (index >= 3) {
                IValidatorTypes.RootParams memory rootParams = IValidatorTypes.RootParams({
                    sourceChainId: CHAINA_ID,
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
                _createAttestation(alice, baseBridgeRoot, 3000, certificateBytes, CHAINA_ID);
            attestationEarly.signature = _signAttestation(
                alice,
                CHAINA_ID,
                attestationEarly.blockNumber,
                attestationEarly.bridgeRoot,
                attestationEarly.stateRoot,
                attestationEarly.timestamp
            );

            vm.prank(alice);
            validatorManagerB.submitAttestation(attestationEarly);
        }

        vm.warp(issuedAtTimestamp + 700);
        {
            IValidatorTypes.BridgeAttestation memory attestationLate =
                _createAttestation(alice, baseBridgeRoot, 3100, certificateBytes, CHAINA_ID);
            attestationLate.signature = _signAttestation(
                alice,
                CHAINA_ID,
                attestationLate.blockNumber,
                attestationLate.bridgeRoot,
                attestationLate.stateRoot,
                attestationLate.timestamp
            );

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
            _createAttestation(bob, baseBridgeRoot, 4000, certificateForChainB, CHAINA_ID);
        attestationOnChainB.signature = _signAttestation(
            bob,
            CHAINA_ID,
            attestationOnChainB.blockNumber,
            attestationOnChainB.bridgeRoot,
            attestationOnChainB.stateRoot,
            attestationOnChainB.timestamp
        );
        vm.prank(bob);
        validatorManagerB.submitAttestation(attestationOnChainB);

        vm.selectFork(FORKA_ID);
        bytes32 satelliteBridgeRoot = _generateBridgeMockRoot(33);
        IValidatorTypes.BridgeAttestation memory attestationOnChainAInvalid =
            _createAttestation(bob, satelliteBridgeRoot, 4100, certificateForChainB, CHAINB_ID);
        attestationOnChainAInvalid.signature = _signAttestation(
            bob,
            CHAINB_ID,
            attestationOnChainAInvalid.blockNumber,
            attestationOnChainAInvalid.bridgeRoot,
            attestationOnChainAInvalid.stateRoot,
            attestationOnChainAInvalid.timestamp
        );
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
            _createAttestation(bob, satelliteBridgeRoot, 4200, certificateForChainA, CHAINB_ID);
        attestationOnChainAValid.signature = _signAttestation(
            bob,
            CHAINB_ID,
            attestationOnChainAValid.blockNumber,
            attestationOnChainAValid.bridgeRoot,
            attestationOnChainAValid.stateRoot,
            attestationOnChainAValid.timestamp
        );
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
                CHAINA_ID
            );
            attestation.signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestation.blockNumber,
                attestation.bridgeRoot,
                attestation.stateRoot,
                attestation.timestamp
            );

            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestation);

            IValidatorTypes.RootParams memory rootParameters = IValidatorTypes.RootParams({
                sourceChainId: CHAINA_ID,
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
                CHAINA_ID
            );
            attestationForFourthValidator.signature = _signAttestation(
                validatorAddresses[3],
                CHAINA_ID,
                attestationForFourthValidator.blockNumber,
                attestationForFourthValidator.bridgeRoot,
                attestationForFourthValidator.stateRoot,
                attestationForFourthValidator.timestamp
            );

            vm.prank(validatorAddresses[3]);
            validatorManagerB.submitAttestation(attestationForFourthValidator);

            IValidatorTypes.RootParams memory rootParameters = IValidatorTypes.RootParams({
                sourceChainId: CHAINA_ID,
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
                validatorAddresses[4], otherBridgeRoot, 8000, certificates[4], CHAINA_ID
            );
            attestationForFifthValidator.signature = _signAttestation(
                validatorAddresses[4],
                CHAINA_ID,
                attestationForFifthValidator.blockNumber,
                attestationForFifthValidator.bridgeRoot,
                attestationForFifthValidator.stateRoot,
                attestationForFifthValidator.timestamp
            );

            vm.prank(validatorAddresses[4]);
            validatorManagerB.submitAttestation(attestationForFifthValidator);

            IValidatorTypes.RootParams memory otherRootParameters = IValidatorTypes.RootParams({
                sourceChainId: CHAINA_ID,
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
            IValidatorTypes.BridgeAttestation memory firstAttestation =
                _createAttestation(validatorAddress, bridgeRootSix, 9000, certificate, CHAINA_ID);
            firstAttestation.signature = _signAttestation(
                validatorAddress,
                CHAINA_ID,
                firstAttestation.blockNumber,
                firstAttestation.bridgeRoot,
                firstAttestation.stateRoot,
                firstAttestation.timestamp
            );
            vm.prank(validatorAddress);
            validatorManagerB.submitAttestation(firstAttestation);
        }

        {
            IValidatorTypes.BridgeAttestation memory duplicateAttestation =
                _createAttestation(validatorAddress, bridgeRootSix, 9000, certificate, CHAINA_ID);
            duplicateAttestation.signature = _signAttestation(
                validatorAddress,
                CHAINA_ID,
                duplicateAttestation.blockNumber,
                duplicateAttestation.bridgeRoot,
                duplicateAttestation.stateRoot,
                duplicateAttestation.timestamp
            );
            vm.prank(validatorAddress);
            vm.expectRevert(IValidatorTypes.AlreadyAttested.selector);
            validatorManagerB.submitAttestation(duplicateAttestation);
        }
    }

    function test_invalidAttestationSignature_isRejected() public {
        vm.selectFork(FORKA_ID);
        _stakeAsUser(alice, 200 ether, FORKA_ID);
        _addValidatorToManager(alice, FORKB_ID);

        vm.selectFork(FORKB_ID);
        (bytes memory certificate,) = _issueCertificate(alice, FORKB_ID, 0);

        IValidatorTypes.BridgeAttestation memory attestation =
            _createAttestation(alice, _generateBridgeMockRoot(77), 7777, certificate, CHAINA_ID);
        attestation.signature = _signAttestation(
            alice,
            CHAINA_ID,
            attestation.blockNumber,
            attestation.bridgeRoot,
            attestation.stateRoot,
            attestation.timestamp
        );
        attestation.stateRoot = keccak256(abi.encodePacked("tampered_state_root"));

        vm.prank(alice);
        vm.expectRevert(IStakeManagerTypes.InvalidBLSSignature.selector);
        validatorManagerB.submitAttestation(attestation);
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
                validatorAddresses[index], bridgeRoot, 10000, certificate, CHAINA_ID
            );
            attestations[index].signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestations[index].blockNumber,
                attestations[index].bridgeRoot,
                attestations[index].stateRoot,
                attestations[index].timestamp
            );
            vm.selectFork(FORKB_ID);
            vm.prank(validatorAddresses[index]);
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
                validatorAddresses[index], bridgeRoot, 10000, certificate, CHAINA_ID
            );
            attestations[index].signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestations[index].blockNumber,
                attestations[index].bridgeRoot,
                attestations[index].stateRoot,
                attestations[index].timestamp
            );
            vm.selectFork(FORKB_ID);
            vm.prank(validatorAddresses[index]);
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

    function test_FinalizeRevertsWhenReplayProcessed() public {
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
                validatorAddresses[index], bridgeRoot, 10000, certificate, CHAINA_ID
            );
            attestations[index].signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestations[index].blockNumber,
                attestations[index].bridgeRoot,
                attestations[index].stateRoot,
                attestations[index].timestamp
            );
            vm.selectFork(FORKB_ID);
            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations[index]);
        }

        IStakeManagerTypes.SlashParams[] memory equivocators =
            _createEquivicators(validatorAddresses, validatorAddresses.length, 0);

        _finalizeWithMocks(attestations, equivocators, root, FORKA_ID);

        vm.selectFork(FORKA_ID);
        vm.expectRevert(IValidatorTypes.FinalizationAlreadyProcessed.selector);
        _finalizeWithMocks(attestations, equivocators, root, FORKA_ID);
    }

    function test_FinalizeSkipsAlreadyInactiveEquivicator() public {
        vm.selectFork(FORKA_ID);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            _stakeAsUser(validatorAddresses[index], 200 ether, FORKA_ID);
            vm.selectFork(FORKB_ID);
            _addValidatorToManager(validatorAddresses[index], FORKB_ID);
        }

        vm.selectFork(FORKA_ID);
        (uint256 minStakeAmount,,,,,,,) = stakeManagerA.ACTIVE_STAKING_CONFIG();
        vm.prank(address(validatorManagerA));
        stakeManagerA.slashValidator(
            IStakeManagerTypes.SlashParams({
                validator: validatorAddresses[0],
                slashAmount: 200 ether - minStakeAmount + 1
            })
        );
        assertEq(
            uint256(validatorManagerA.getValidator(validatorAddresses[0]).status),
            uint256(IValidatorTypes.ValidatorStatus.Inactive)
        );

        bytes32 root = _generateBridgeMockRoot(2);
        IValidatorTypes.BridgeAttestation[] memory attestations =
            new IValidatorTypes.BridgeAttestation[](5);
        bytes32 bridgeRoot = _generateBridgeMockRoot(9);
        for (uint256 index = 0; index < validatorAddresses.length; index++) {
            (bytes memory certificate,) = _issueCertificate(validatorAddresses[index], FORKB_ID, 0);

            attestations[index] = _createAttestation(
                validatorAddresses[index], bridgeRoot, 10001, certificate, CHAINA_ID
            );
            attestations[index].signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestations[index].blockNumber,
                attestations[index].bridgeRoot,
                attestations[index].stateRoot,
                attestations[index].timestamp
            );
            vm.selectFork(FORKB_ID);
            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations[index]);
        }

        IStakeManagerTypes.SlashParams[] memory equivocators =
            new IStakeManagerTypes.SlashParams[](1);
        equivocators[0] =
            IStakeManagerTypes.SlashParams({validator: validatorAddresses[0], slashAmount: 1 ether});

        _finalizeWithMocks(attestations, equivocators, root, FORKA_ID);

        vm.selectFork(FORKA_ID);
        assertEq(
            validatorManagerA.getValidator(validatorAddresses[0]).invalidAttestations,
            0,
            "inactive validator should not be reslashed"
        );
        for (uint256 index = 1; index < validatorAddresses.length; index++) {
            assertEq(validatorManagerA.getValidator(validatorAddresses[index]).attestationCount, 1);
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
                validatorAddresses[index], bridgeRoot, 10000, certificate, CHAINA_ID
            );
            attestations[index].signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestations[index].blockNumber,
                attestations[index].bridgeRoot,
                attestations[index].stateRoot,
                attestations[index].timestamp
            );
            vm.selectFork(FORKB_ID);
            vm.prank(validatorAddresses[index]);
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
                validatorAddresses[index], bridgeRoot1, 10000, certificate, CHAINA_ID
            );
            attestations1[index].signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestations1[index].blockNumber,
                attestations1[index].bridgeRoot,
                attestations1[index].stateRoot,
                attestations1[index].timestamp
            );
            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations1[index]);
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
                validatorAddresses[index], bridgeRoot2, 10001, certificate, CHAINA_ID
            );
            attestations2[index].signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestations2[index].blockNumber,
                attestations2[index].bridgeRoot,
                attestations2[index].stateRoot,
                attestations2[index].timestamp
            );
            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations2[index]);
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
                validatorAddresses[index], bridgeRoot3, 10002, certificate, CHAINA_ID
            );
            attestations3[index].signature = _signAttestation(
                validatorAddresses[index],
                CHAINA_ID,
                attestations3[index].blockNumber,
                attestations3[index].bridgeRoot,
                attestations3[index].stateRoot,
                attestations3[index].timestamp
            );
            vm.prank(validatorAddresses[index]);
            validatorManagerB.submitAttestation(attestations3[index]);
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

    function test_finalizationAcceptsNonLocalAttestedChain() public {
        vm.selectFork(FORKA_ID);
        _stakeAsUser(alice, 200 ether, FORKA_ID);

        IValidatorTypes.BridgeAttestation[] memory attestations =
            new IValidatorTypes.BridgeAttestation[](1);
        attestations[0] = IValidatorTypes.BridgeAttestation({
            blockNumber: 50_000,
            bridgeRoot: _generateBridgeMockRoot(91),
            stateRoot: keccak256(abi.encodePacked("remote_state_root")),
            sourceChainId: CHAINB_ID,
            timestamp: block.timestamp,
            validator: alice,
            certificate: "",
            signature: [uint256(0), uint256(0)]
        });

        IStakeManagerTypes.SlashParams[] memory noEquivocators =
            new IStakeManagerTypes.SlashParams[](0);

        _finalizeWithMocks(attestations, noEquivocators, _generateBridgeMockRoot(92), FORKA_ID);

        assertEq(validatorManagerA.getValidator(alice).attestationCount, 1);
    }
}
