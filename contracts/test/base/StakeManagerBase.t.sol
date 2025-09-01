// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakeManager} from "../../src/stake/StakeManager.sol";
import {ValidatorManager} from "../../src/validator/ValidatorManager.sol";
import {IStakeManagerTypes} from "../../src/stake/IStakeManagerTypes.sol";
import {IValidatorTypes} from "../../src/validator/IValidatorManager.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Test, console} from "forge-std/Test.sol";
import {BLS} from "solbls/BLS.sol";
import "./BridgeBase.t.sol";

contract StakeManagerBaseTest is BridgeBaseTest, IStakeManagerTypes {
    using stdJson for string;
    using BLS for *;

    StakeManager public stakeManagerA;
    ValidatorManager public validatorManagerA;
    StakeManager public stakeManagerB;
    ValidatorManager public validatorManagerB;
    StakeManagerConfig public testConfig;
    bytes32 public testConfigVersionA;
    bytes32 public testConfigVersionB;

    struct BlsTestData {
        string privateKey;
        string[4] publicKey;
        string[2] proofOfPossession;
        string walletAddress;
        string domain;
        string[2] messageHash;
    }

    BlsTestData[] public blsTestData;

    mapping(address => BlsTestData) public validatorBlsData;

    function setUp() public override noGasMetering {
        super.setUp();
        vm.selectFork(FORKA_ID);
        _loadBlsTestData();
        _deployStakeManager(FORKA_ID);
        _setupDefaultConfig(FORKA_ID);
        _deployStakeManager(FORKB_ID);
        _setupDefaultConfig(FORKB_ID);
    }

    function _scanArrayLengthByKey(
        string memory json,
        string memory field
    )
        internal
        pure
        returns (uint256 len)
    {
        for (uint256 i = 0;; ++i) {
            string memory key = string.concat("$[", vm.toString(i), "].", field);
            try vm.parseJsonString(json, key) returns (string memory) {
                len = i + 1;
            } catch {
                break;
            }
        }
    }

    function _loadBlsTestData() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/test/data/bls.json");
        if (!vm.exists(path)) revert("BLS test data required for tests");

        string memory json = vm.readFile(path);
        if (bytes(json).length == 0) revert("Empty BLS test data file");

        bool isArray = _isJsonArray(json);

        uint256 length = isArray ? _scanArrayLengthByKey(json, "private_key") : 1;
        require(length > 0, "No valid BLS test data found");
        console.log("Parsing %s BLS test case(s)", length);

        for (uint256 i = 0; i < length; i++) {
            BlsTestData memory data;
            string memory base = isArray ? string.concat("$[", vm.toString(i), "]") : "$";

            data.privateKey = vm.parseJsonString(json, string.concat(base, ".private_key"));
            data.walletAddress = vm.parseJsonString(json, string.concat(base, ".wallet_address"));
            data.domain = vm.parseJsonString(json, string.concat(base, ".domain"));

            data.publicKey[0] = vm.parseJsonString(json, string.concat(base, ".public_key[0]"));
            data.publicKey[1] = vm.parseJsonString(json, string.concat(base, ".public_key[1]"));
            data.publicKey[2] = vm.parseJsonString(json, string.concat(base, ".public_key[2]"));
            data.publicKey[3] = vm.parseJsonString(json, string.concat(base, ".public_key[3]"));

            data.proofOfPossession[0] =
                vm.parseJsonString(json, string.concat(base, ".proof_of_possession[0]"));
            data.proofOfPossession[1] =
                vm.parseJsonString(json, string.concat(base, ".proof_of_possession[1]"));

            data.messageHash[0] = vm.parseJsonString(json, string.concat(base, ".message_hash[0]"));
            data.messageHash[1] = vm.parseJsonString(json, string.concat(base, ".message_hash[1]"));

            blsTestData.push(data);
            validatorBlsData[vm.parseAddress(data.walletAddress)] = data;
            console.log("Loaded BLS data for address:", data.walletAddress);
        }
    }

    function _isJsonArray(string memory json) internal pure returns (bool) {
        bytes memory jsonBytes = bytes(json);
        if (jsonBytes.length == 0) return false;

        for (uint256 i = 0; i < jsonBytes.length; i++) {
            if (
                jsonBytes[i] != 0x20 && jsonBytes[i] != 0x09 && jsonBytes[i] != 0x0A
                    && jsonBytes[i] != 0x0D
            ) {
                return jsonBytes[i] == 0x5B;
            }
        }
        return false;
    }

    function _deployStakeManager(uint256 forkId) internal {
        vm.selectFork(forkId);
        vm.startPrank(owner);
        StakeManagerConfig memory stakeConfig = StakeManagerConfig({
            minStakeAmount: 100 ether,
            minWithdrawAmount: 1 ether,
            minUnstakeDelay: 7 days,
            correctProofReward: 1 ether,
            incorrectProofPenalty: 2 ether,
            maxMissedProofs: 5,
            slashingRate: 1000,
            stakingToken: address(TOKEN_CHAINA)
        });

        if (forkId == CHAINA_ID) {
            address validatorManagerAddr = Upgrades.deployUUPSProxy(
                "ValidatorManager.sol",
                abi.encodeCall(ValidatorManager.initialize, (owner, SP1_VERIFIER, PROGRAM_VKEY)),
                options
            );
            validatorManagerA = ValidatorManager(validatorManagerAddr);

            address stakeManagerAddr = Upgrades.deployUUPSProxy(
                "StakeManager.sol",
                abi.encodeCall(StakeManager.initialize, (stakeConfig, validatorManagerAddr)),
                options
            );
            stakeManagerA = StakeManager(stakeManagerAddr);
        } else {
            address validatorManagerAddr = Upgrades.deployUUPSProxy(
                "ValidatorManager.sol",
                abi.encodeCall(ValidatorManager.initialize, (owner, SP1_VERIFIER, PROGRAM_VKEY)),
                options
            );

            validatorManagerB = ValidatorManager(validatorManagerAddr);
            address stakeManagerAddr = Upgrades.deployUUPSProxy(
                "StakeManager.sol",
                abi.encodeCall(StakeManager.initialize, (stakeConfig, validatorManagerAddr)),
                options
            );
            stakeManagerB = StakeManager(stakeManagerAddr);
        }

        vm.stopPrank();
    }

    function _setupDefaultConfig(uint256 forkId) internal {
        vm.selectFork(forkId);
        testConfig = StakeManagerConfig({
            minStakeAmount: 100 ether,
            minWithdrawAmount: 10 ether,
            minUnstakeDelay: 7 days,
            correctProofReward: 1 ether,
            incorrectProofPenalty: 2 ether,
            maxMissedProofs: 5,
            slashingRate: 1000,
            stakingToken: address(TOKEN_CHAINA)
        });
        if (forkId == CHAINA_ID) {
            testConfigVersionA = stakeManagerA.getStakeVersion(testConfig);
        } else {
            testConfigVersionB = stakeManagerB.getStakeVersion(testConfig);
        }
    }

    function _stakeAsUser(address user, uint256 amount, uint256 forkId) internal {
        BlsTestData memory data = validatorBlsData[user];
        vm.selectFork(forkId);
        vm.startPrank(user);
        if (forkId == CHAINA_ID) {
            TOKEN_CHAINA.approve(address(stakeManagerA), amount);
        } else {
            TOKEN_CHAINA.approve(address(stakeManagerB), amount);
        }

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];

        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];
        if (forkId == CHAINA_ID) {
            StakeParams memory params =
                StakeParams({stakeAmount: amount, stakeVersion: testConfigVersionA});

            BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

            stakeManagerA.stake(params, proof);
        } else {
            StakeParams memory params =
                StakeParams({stakeAmount: amount, stakeVersion: testConfigVersionB});

            BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});

            stakeManagerB.stake(params, proof);
        }
        vm.stopPrank();
    }

    function _beginUnstakingAsValidator(
        address validator,
        uint256 amount,
        uint256 forkId
    )
        internal
    {
        vm.selectFork(forkId);
        UnstakingParams memory params = UnstakingParams({
            stakeAmount: amount,
            stakeVersion: forkId == CHAINA_ID ? testConfigVersionA : testConfigVersionB,
            validator: validator
        });
        address manager =
            forkId == CHAINA_ID ? address(validatorManagerA) : address(validatorManagerB);
        vm.prank(manager);
        if (forkId == CHAINA_ID) {
            stakeManagerA.beginUnstaking(params);
        } else {
            stakeManagerB.beginUnstaking(params);
        }
    }

    function _distributeRewardsToValidator(address validator, uint256 forkId) internal {
        BlsTestData memory data = validatorBlsData[validator];

        IValidatorTypes.ValidatorInfo[] memory validators = new IValidatorTypes.ValidatorInfo[](1);
        validators[0] = IValidatorTypes.ValidatorInfo({
            blsPublicKey: [
                vm.parseUint(data.publicKey[0]),
                vm.parseUint(data.publicKey[1]),
                vm.parseUint(data.publicKey[2]),
                vm.parseUint(data.publicKey[3])
            ],
            wallet: validator,
            status: IValidatorTypes.ValidatorStatus.Active,
            attestationCount: 100,
            invalidAttestations: 10
        });

        RewardsParams memory params =
            RewardsParams({recipients: validators, epoch: 1, epochDuration: 600});
        address manager =
            forkId == CHAINA_ID ? address(validatorManagerA) : address(validatorManagerB);
        vm.prank(manager);
        if (forkId == CHAINA_ID) {
            stakeManagerA.distributeRewards(params);
        } else {
            stakeManagerB.distributeRewards(params);
        }
    }
}
