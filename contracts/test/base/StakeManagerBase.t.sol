// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakeManager} from "../../src/stake/StakeManager.sol";
import {BridgeToken} from "../../src/test/BridgeToken.sol";
import {ValidatorManager} from "../../src/validator/ValidatorManager.sol";
import {IStakeManagerTypes} from "../../src/stake/IStakeManagerTypes.sol";
import {IValidatorTypes} from "../../src/validator/IValidatorManager.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BLS} from "solbls/BLS.sol";
import {BridgeBaseTest} from "./BridgeBase.t.sol";
import {console} from "forge-std/Test.sol";

abstract contract StakeManagerBaseTest is BridgeBaseTest, IStakeManagerTypes {
    using stdJson for string;
    using BLS for *;

    uint256 internal constant MAX_JSON_SCAN_ITERATIONS = 1000;

    uint256 internal constant DEFAULT_MIN_STAKE = 100 ether;
    uint256 internal constant DEFAULT_MIN_WITHDRAW = 1 ether;
    uint256 internal constant DEFAULT_UNSTAKE_DELAY = 2 days;
    uint256 internal constant DEFAULT_PROOF_REWARD = 1 ether;
    uint256 internal constant DEFAULT_PROOF_PENALTY = 2 ether;
    uint256 internal constant DEFAULT_REWARD_BALANCE = 10_000_000 ether;

    uint32 internal constant DEFAULT_MAX_MISSED_PROOFS = 5;
    uint32 internal constant DEFAULT_SLASHING_RATE = 1000;

    uint8 internal constant JSON_SPACE = 0x20;
    uint8 internal constant JSON_TAB = 0x09;
    uint8 internal constant JSON_NEWLINE = 0x0A;
    uint8 internal constant JSON_CARRIAGE_RETURN = 0x0D;
    uint8 internal constant JSON_ARRAY_START = 0x5B;

    StakeManager public stakeManagerA;
    ValidatorManager public validatorManagerA;
    StakeManager public stakeManagerB;
    ValidatorManager public validatorManagerB;

    StakeManagerConfig public testConfigA;
    StakeManagerConfig public testConfigB;

    bytes32 public testConfigVersionA;
    bytes32 public testConfigVersionB;

    struct BlsTestData {
        string privateKey;
        string[4] publicKey;
        string walletAddress;
        string domainStake;
        string domainValidator;
    }

    struct ProofData {
        string[2] messageHashStake;
        string[2] messageHashValidator;
        string[2] proofOfPossessionStake;
        string[2] proofOfPossessionValidator;
        uint256 chainId;
    }

    mapping(address => BlsTestData) public validatorBlsData;
    mapping(address => mapping(uint256 => ProofData)) public validatorProofData;

    function setUp() public virtual override noGasMetering {
        super.setUp();
        _loadBlsTestData();
        _deployStakeManager(FORKA_ID);
        _deployStakeManager(FORKB_ID);
        vm.label(address(stakeManagerA), "stakeManagerA");
        vm.label(address(stakeManagerB), "stakeManagerB");
        vm.label(address(validatorManagerA), "validatorManagerA");
        vm.label(address(validatorManagerB), "validatorManagerB");
    }

    function _scanArrayLengthByKey(
        string memory json,
        string memory field
    )
        internal
        pure
        returns (uint256 len)
    {
        for (uint256 i = 0; i < MAX_JSON_SCAN_ITERATIONS; ++i) {
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

        require(vm.exists(path), "BLS test data file not found");

        string memory json = vm.readFile(path);
        require(bytes(json).length > 0, "BLS test data file is empty");

        bool isArray = _isJsonArray(json);
        uint256 length = isArray ? _scanArrayLengthByKey(json, "private_key") : 1;
        require(length > 0, "No valid BLS test data found in file");

        console.log("Parsing %s BLS test case(s)", length);

        for (uint256 i = 0; i < length; i++) {
            _parseBlsDataAtIndex(json, i, isArray);
        }
    }

    function _parseBlsDataAtIndex(string memory json, uint256 index, bool isArray) internal {
        string memory base = isArray ? string.concat("$[", vm.toString(index), "]") : "$";

        BlsTestData memory data;

        data.privateKey = vm.parseJsonString(json, string.concat(base, ".private_key"));
        data.walletAddress = vm.parseJsonString(json, string.concat(base, ".wallet_address"));
        data.domainStake = vm.parseJsonString(json, string.concat(base, ".domain_staking_manager"));
        data.domainValidator =
            vm.parseJsonString(json, string.concat(base, ".domain_validator_manager"));

        for (uint256 i = 0; i < 4; i++) {
            data.publicKey[i] =
                vm.parseJsonString(json, string.concat(base, ".public_key[", vm.toString(i), "]"));
        }

        address walletAddr = vm.parseAddress(data.walletAddress);
        require(walletAddr != address(0), "Invalid wallet address in BLS test data");

        validatorBlsData[walletAddr] = data;

        uint256 proofCount = 0;
        for (uint256 proofIdx = 0; proofIdx < MAX_JSON_SCAN_ITERATIONS; proofIdx++) {
            string memory proofBase = string.concat(base, ".proof[", vm.toString(proofIdx), "]");
            try vm.parseJsonString(json, string.concat(proofBase, ".message_hash_stake_manager[0]"))
            returns (string memory) {
                proofCount++;
            } catch {
                break;
            }
        }

        require(proofCount > 0 && proofCount <= 2, "Expected 1 or 2 proof entries per validator");

        console.log("Loaded BLS data for address:", data.walletAddress);
        console.log("  Found %s proof entries", proofCount);

        for (uint256 proofIdx = 0; proofIdx < proofCount; proofIdx++) {
            string memory proofBase = string.concat(base, ".proof[", vm.toString(proofIdx), "]");

            ProofData memory proofData;

            proofData.chainId = vm.parseJsonUint(json, string.concat(proofBase, ".chain_id"));

            for (uint256 i = 0; i < 2; i++) {
                proofData.messageHashStake[i] = vm.parseJsonString(
                    json,
                    string.concat(proofBase, ".message_hash_stake_manager[", vm.toString(i), "]")
                );

                proofData.messageHashValidator[i] = vm.parseJsonString(
                    json,
                    string.concat(
                        proofBase, ".message_hash_validator_manager[", vm.toString(i), "]"
                    )
                );

                proofData.proofOfPossessionStake[i] = vm.parseJsonString(
                    json,
                    string.concat(
                        proofBase, ".proof_of_possession_stake_manager[", vm.toString(i), "]"
                    )
                );

                proofData.proofOfPossessionValidator[i] = vm.parseJsonString(
                    json,
                    string.concat(
                        proofBase, ".proof_of_possession_validator_manager[", vm.toString(i), "]"
                    )
                );
            }

            validatorProofData[walletAddr][proofData.chainId] = proofData;

            console.log("  Proof[%s] -> ChainId: %s", proofIdx, proofData.chainId);
            console.log("    PoP Stake[0]: %s", proofData.proofOfPossessionStake[0]);
            console.log("    PoP Validator[0]: %s", proofData.proofOfPossessionValidator[0]);
        }
    }

    function _isJsonArray(string memory json) internal pure returns (bool) {
        bytes memory jsonBytes = bytes(json);
        if (jsonBytes.length == 0) return false;

        for (uint256 i = 0; i < jsonBytes.length; i++) {
            uint8 char = uint8(jsonBytes[i]);
            if (
                char != JSON_SPACE && char != JSON_TAB && char != JSON_NEWLINE
                    && char != JSON_CARRIAGE_RETURN
            ) {
                return char == JSON_ARRAY_START;
            }
        }
        return false;
    }

    function _deployStakeManager(uint256 forkId) internal {
        vm.selectFork(forkId);

        _prankOwnerOnChain(forkId);

        if (forkId == FORKA_ID) {
            (stakeManagerA, validatorManagerA, testConfigA, testConfigVersionA) =
                _deployStakeManagerForChain(address(TOKEN_CHAINA), true);
        } else if (forkId == FORKB_ID) {
            (stakeManagerB, validatorManagerB, testConfigB, testConfigVersionB) =
                _deployStakeManagerForChain(address(TOKEN_CHAINB), false);
        } else {
            revert("Invalid fork ID provided");
        }

        vm.stopPrank();
    }

    function _deployStakeManagerForChain(
        address _stakingToken,
        bool _enableStaking
    )
        internal
        returns (
            StakeManager stakeManager,
            ValidatorManager validatorManager,
            StakeManagerConfig memory config,
            bytes32 configVersion
        )
    {
        config = StakeManagerConfig({
            minStakeAmount: DEFAULT_MIN_STAKE,
            minWithdrawAmount: DEFAULT_MIN_WITHDRAW,
            minUnstakeDelay: DEFAULT_UNSTAKE_DELAY,
            correctProofReward: DEFAULT_PROOF_REWARD,
            incorrectProofPenalty: DEFAULT_PROOF_PENALTY,
            maxMissedProofs: DEFAULT_MAX_MISSED_PROOFS,
            slashingRate: DEFAULT_SLASHING_RATE,
            stakingToken: _stakingToken
        });

        address stakeManagerAddr = Upgrades.deployUUPSProxy(
            "StakeManager.sol",
            abi.encodeCall(StakeManager.initialize, (config, address(0))),
            options
        );
        address validatorManagerAddr = Upgrades.deployUUPSProxy(
            "ValidatorManager.sol",
            abi.encodeCall(ValidatorManager.initialize, (SP1_VERIFIER, PROGRAM_VKEY)),
            options
        );
        validatorManager = ValidatorManager(validatorManagerAddr);
        stakeManager = StakeManager(stakeManagerAddr);
        BridgeToken(_stakingToken).approve(stakeManagerAddr, type(uint256).max);
        if (_enableStaking) {
            stakeManager.updateValidatorManager(validatorManagerAddr);
            validatorManager.updateStakingManager(stakeManagerAddr);
            configVersion = stakeManager.getStakeVersion(config);
        }
    }

    function _topupRewards(uint256 forkId, uint256 amount, address rewardsToken) internal {
        _prankOwnerOnChain(forkId);
        if (forkId == FORKA_ID) {
            stakeManagerA.transferToken(rewardsToken, amount);
        } else {
            stakeManagerB.transferToken(rewardsToken, amount);
        }
    }

    function getValidatorProofData(
        address validator,
        uint256 chainId
    )
        public
        view
        returns (ProofData memory proofData)
    {
        return validatorProofData[validator][chainId];
    }

    function getValidatorBlsData(address validator) public view returns (BlsTestData memory data) {
        return validatorBlsData[validator];
    }

    function hasValidProofData(
        address validator,
        uint256 chainId
    )
        public
        view
        returns (bool isValid)
    {
        ProofData memory proofData = validatorProofData[validator][chainId];
        return proofData.chainId == chainId && bytes(proofData.proofOfPossessionStake[0]).length > 0;
    }

    function getValidatorAttestationSignature(
        address validator,
        uint256 forkId
    )
        public
        returns (uint256[2] memory signature)
    {
        vm.selectFork(forkId);
        uint256 chainId = block.chainid;

        ProofData memory proofData = validatorProofData[validator][chainId];
        require(proofData.chainId == chainId, "No proof data for specified chain");

        signature[0] = vm.parseUint(proofData.proofOfPossessionValidator[0]);
        signature[1] = vm.parseUint(proofData.proofOfPossessionValidator[1]);
    }

    function _stakeAsUser(address user, uint256 amount, uint256 forkId) internal {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Stake amount must be greater than zero");

        vm.selectFork(forkId);
        uint256 chainId = block.chainid;

        BlsTestData memory data = validatorBlsData[user];
        require(bytes(data.walletAddress).length > 0, "No BLS data found for user");

        ProofData memory proofData = validatorProofData[user][chainId];
        require(proofData.chainId == chainId, "No proof data for specified chain");

        console.log("Staking for user:", user);
        console.log("  Fork ID:", forkId);
        console.log("  Chain ID:", chainId);
        console.log("  Using PoP Stake:", proofData.proofOfPossessionStake[0]);
        console.log("  Public Key[0]:", data.publicKey[0]);

        vm.startPrank(user);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];

        uint256[2] memory signature = [
            vm.parseUint(proofData.proofOfPossessionStake[0]),
            vm.parseUint(proofData.proofOfPossessionStake[1])
        ];

        if (forkId == FORKA_ID) {
            TOKEN_CHAINA.approve(address(stakeManagerA), amount);
            StakeParams memory params =
                StakeParams({stakeAmount: amount, stakeVersion: testConfigVersionA});
            BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});
            stakeManagerA.stake(params, proof);
        } else if (forkId == FORKB_ID) {
            TOKEN_CHAINB.approve(address(stakeManagerB), amount);
            StakeParams memory params =
                StakeParams({stakeAmount: amount, stakeVersion: testConfigVersionB});
            BlsOwnerShip memory proof = BlsOwnerShip({signature: signature, pubkey: pubkey});
            stakeManagerB.stake(params, proof);
        } else {
            revert("Invalid fork ID");
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
        require(validator != address(0), "Invalid validator address");
        require(amount > 0, "Unstake amount must be greater than zero");

        vm.selectFork(forkId);

        UnstakingParams memory params = UnstakingParams({stakeAmount: amount});

        vm.prank(validator);

        if (forkId == FORKA_ID) {
            stakeManagerA.beginUnstaking(params);
        } else if (forkId == FORKB_ID) {
            stakeManagerB.beginUnstaking(params);
        } else {
            revert("Invalid fork ID");
        }
    }

    function _distributeRewardsToValidator(
        address validator,
        uint256 forkId,
        uint256 epoch
    )
        internal
    {
        require(validator != address(0), "Invalid validator address");

        BlsTestData memory data = validatorBlsData[validator];
        require(bytes(data.walletAddress).length > 0, "No BLS data found for validator");

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
            RewardsParams({recipients: validators, epoch: epoch, epochDuration: 600});

        address manager =
            forkId == FORKA_ID ? address(validatorManagerA) : address(validatorManagerB);

        vm.prank(manager);

        if (forkId == FORKA_ID) {
            stakeManagerA.distributeRewards(params);
        } else if (forkId == FORKB_ID) {
            stakeManagerB.distributeRewards(params);
        } else {
            revert("Invalid fork ID");
        }
    }
}
