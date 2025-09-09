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

/// @title StakeManagerBaseTest
/// @notice Base test contract for StakeManager functionality with BLS signature support
/// @dev Extends BridgeBaseTest to provide dual-chain testing capabilities for staking operations
abstract contract StakeManagerBaseTest is BridgeBaseTest, IStakeManagerTypes {
    using stdJson for string;
    using BLS for *;

    /// @dev Maximum iterations allowed when scanning JSON arrays to prevent infinite loops
    uint256 internal constant MAX_JSON_SCAN_ITERATIONS = 1000;

    /// @dev Default test configuration values
    uint256 internal constant DEFAULT_MIN_STAKE = 100 ether;
    uint256 internal constant DEFAULT_MIN_WITHDRAW = 1 ether;
    uint256 internal constant DEFAULT_UNSTAKE_DELAY = 2 days;
    uint256 internal constant DEFAULT_PROOF_REWARD = 1 ether;
    uint256 internal constant DEFAULT_PROOF_PENALTY = 2 ether;
    uint256 internal constant DEFAULT_REWARD_BALANCE = 10_000_000 ether;

    uint32 internal constant DEFAULT_MAX_MISSED_PROOFS = 5;
    uint32 internal constant DEFAULT_SLASHING_RATE = 1000;

    /// @dev JSON parsing constants
    uint8 internal constant JSON_SPACE = 0x20;
    uint8 internal constant JSON_TAB = 0x09;
    uint8 internal constant JSON_NEWLINE = 0x0A;
    uint8 internal constant JSON_CARRIAGE_RETURN = 0x0D;

    /// @notice '['
    uint8 internal constant JSON_ARRAY_START = 0x5B;

    /// @notice StakeManager contract instance for Chain A
    StakeManager public stakeManagerA;

    /// @notice ValidatorManager contract instance for Chain A
    ValidatorManager public validatorManagerA;

    /// @notice StakeManager contract instance for Chain B
    StakeManager public stakeManagerB;

    /// @notice ValidatorManager contract instance for Chain B
    ValidatorManager public validatorManagerB;

    /// @notice Staking configuration for Chain A
    StakeManagerConfig public testConfigA;

    /// @notice Staking configuration for Chain B
    StakeManagerConfig public testConfigB;

    /// @notice Configuration version hash for Chain A
    bytes32 public testConfigVersionA;

    /// @notice Configuration version hash for Chain B
    bytes32 public testConfigVersionB;

    /// @notice Structure containing BLS test data for validators
    /// @param privateKey BLS private key as hex string
    /// @param publicKey BLS public key components (4 elements)
    /// @param proofOfPossession BLS proof of possession signature (2 elements)
    /// @param walletAddress Ethereum wallet address
    /// @param domain BLS domain separator
    /// @param messageHash Message hash used for signing (2 elements)
    struct BlsTestData {
        string privateKey;
        string[4] publicKey;
        string[2] proofOfPossession;
        string walletAddress;
        string domain;
        string[2] messageHash;
    }

    /// @notice Array of all loaded BLS test data
    BlsTestData[] public blsTestData;

    /// @notice Mapping from validator address to their BLS test data
    mapping(address => BlsTestData) public validatorBlsData;

    function setUp() public override noGasMetering {
        super.setUp();
        _loadBlsTestData();
        _deployStakeManager(FORKA_ID);
        _deployStakeManager(FORKB_ID);
        vm.label(address(stakeManagerA), "stakeManagerA");
        vm.label(address(stakeManagerB), "stakeManagerB");
        vm.label(address(validatorManagerA), "validatorManagerA");
        vm.label(address(validatorManagerB), "validatorManagerB");
    }

    /// @notice Scans JSON array length by checking for a specific field
    /// @dev Protected against infinite loops with MAX_JSON_SCAN_ITERATIONS limit
    /// @param json The JSON string to scan
    /// @param field The field name to look for in each array element
    /// @return len The number of array elements found
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

    /// @notice Loads BLS test data from JSON file
    /// @dev Reads from test/data/bls.json and supports both single object and array formats
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
            BlsTestData memory data = _parseBlsDataAtIndex(json, i, isArray);

            address walletAddr = vm.parseAddress(data.walletAddress);
            require(walletAddr != address(0), "Invalid wallet address in BLS test data");

            blsTestData.push(data);
            validatorBlsData[walletAddr] = data;
            console.log("Loaded BLS data for address:", data.walletAddress);
        }
    }

    /// @notice Parses BLS test data at a specific index
    /// @param json The JSON string containing test data
    /// @param index The index to parse (ignored if not array)
    /// @param isArray Whether the JSON is an array format
    /// @return data The parsed BLS test data
    function _parseBlsDataAtIndex(
        string memory json,
        uint256 index,
        bool isArray
    )
        internal
        pure
        returns (BlsTestData memory data)
    {
        string memory base = isArray ? string.concat("$[", vm.toString(index), "]") : "$";

        data.privateKey = vm.parseJsonString(json, string.concat(base, ".private_key"));
        data.walletAddress = vm.parseJsonString(json, string.concat(base, ".wallet_address"));
        data.domain = vm.parseJsonString(json, string.concat(base, ".domain"));

        for (uint256 i = 0; i < 4; i++) {
            data.publicKey[i] =
                vm.parseJsonString(json, string.concat(base, ".public_key[", vm.toString(i), "]"));
        }

        for (uint256 i = 0; i < 2; i++) {
            data.proofOfPossession[i] = vm.parseJsonString(
                json, string.concat(base, ".proof_of_possession[", vm.toString(i), "]")
            );
        }

        for (uint256 i = 0; i < 2; i++) {
            data.messageHash[i] =
                vm.parseJsonString(json, string.concat(base, ".message_hash[", vm.toString(i), "]"));
        }
    }

    /// @notice Determines if a JSON string represents an array
    /// @dev Checks for opening bracket '[' after skipping whitespace
    /// @param json The JSON string to check
    /// @return True if the JSON represents an array, false otherwise
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

    /// @notice Deploys StakeManager and ValidatorManager contracts on specified fork
    /// @dev Creates UUPS proxy contracts with appropriate initialization parameters
    /// @param forkId The fork identifier (FORKA_ID or FORKB_ID)
    function _deployStakeManager(uint256 forkId) internal {
        vm.selectFork(forkId);

        _prankOwnerOnChain(forkId);

        if (forkId == FORKA_ID) {
            (stakeManagerA, validatorManagerA, testConfigA, testConfigVersionA) =
                _deployStakeManagerForChain(address(TOKEN_CHAINA));
        } else if (forkId == FORKB_ID) {
            (stakeManagerB, validatorManagerB, testConfigB, testConfigVersionB) =
                _deployStakeManagerForChain(address(TOKEN_CHAINB));
        } else {
            revert("Invalid fork ID provided");
        }

        vm.stopPrank();
    }

    /// @notice Internal helper to deploy contracts for a specific chain
    /// @param _stakingToken ERC20 used for staking
    function _deployStakeManagerForChain(address _stakingToken)
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
        stakeManager.transferToken(_stakingToken, DEFAULT_REWARD_BALANCE);
        stakeManager.updateValidatorManager(validatorManagerAddr);
        validatorManager.updateStakingManager(stakeManagerAddr);
        configVersion = stakeManager.getStakeVersion(config);
    }

    /// @notice Stakes tokens as a specific user with their BLS credentials
    /// @dev Requires the user to have BLS test data loaded
    /// @param user The address of the user staking
    /// @param amount The amount of tokens to stake
    /// @param forkId The fork identifier where staking occurs
    function _stakeAsUser(address user, uint256 amount, uint256 forkId) internal {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Stake amount must be greater than zero");

        BlsTestData memory data = validatorBlsData[user];
        require(bytes(data.walletAddress).length > 0, "No BLS data found for user");

        vm.selectFork(forkId);
        vm.startPrank(user);

        uint256[4] memory pubkey = [
            vm.parseUint(data.publicKey[0]),
            vm.parseUint(data.publicKey[1]),
            vm.parseUint(data.publicKey[2]),
            vm.parseUint(data.publicKey[3])
        ];

        uint256[2] memory signature =
            [vm.parseUint(data.proofOfPossession[0]), vm.parseUint(data.proofOfPossession[1])];

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

    /// @notice Begins the unstaking process for a validator
    /// @dev Must be called by the ValidatorManager contract
    /// @param validator The address of the validator to unstake
    /// @param amount The amount to unstake
    /// @param forkId The fork identifier where unstaking occurs
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

    /// @notice Distributes rewards to a validator based on their performance
    /// @dev Uses the validator's BLS data to create reward distribution parameters
    /// @param validator The address of the validator receiving rewards
    /// @param forkId The fork identifier where rewards are distributed
    /// @param epoch The current epoch to use
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
