// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {BridgeToken} from "../../src/test/BridgeToken.sol";
import {Bridge} from "../../src/bridge/Bridge.sol";

import {StakeManager} from "../../src/stake/StakeManager.sol";
import {IStakeManagerTypes} from "../../src/stake/IStakeManagerTypes.sol";

import {ValidatorManager} from "../../src/validator/ValidatorManager.sol";

import {JsonDeploymentHandler} from "../util/JsonDeploymentHandler.sol";
import {StringUtil} from "../util/StringUtil.sol";

/// @title BridgeDeployScript
/// @notice Deploys Bridge, StakeManager, and ValidatorManager for the current chain.
/// @dev Uses UUPS proxies for upgradeable contracts. Addresses are persisted through JsonDeploymentHandler.
contract BridgeDeployScript is Script, JsonDeploymentHandler {
    using StringUtil for uint256;

    /// @notice Default token supply for chain-local test bridge tokens.
    uint256 public constant DEFAULT_TOKEN_SUPPLY = 1_000_000_000 ether;

    /// @notice Default bridge liquidity minted on every chain-local token.
    uint256 public constant DEFAULT_BRIDGE_LIQUIDITY_SUPPLY = 500_000_000 ether;

    /// @notice Default native ETH liquidity prefunded on every bridge.
    uint256 public constant DEFAULT_NATIVE_BRIDGE_LIQUIDITY_SUPPLY = 1_000 ether;

    /// @notice UUPS deployment options.
    Options public options;

    /// @notice Deployed token A (chain-local).
    BridgeToken public tokenA;

    /// @notice Deployed token B (chain-local).
    BridgeToken public tokenB;

    /// @notice Deployed Bridge proxy (chain-local).
    Bridge public bridge;

    /// @notice Deployed StakeManager proxy (chain-local).
    StakeManager public stakeManager;

    /// @notice Deployed ValidatorManager proxy (chain-local).
    ValidatorManager public validatorManager;
    uint256 public immutable BASE_CHAIN = 31339;

    /// @notice Per-chain deployment configuration.
    struct ChainConfig {
        // Token metadata
        string tokenAName;
        string tokenASymbol;
        string tokenBName;
        string tokenBSymbol;
        // Node manager for certificate verification (chain-local)
        address nodeManager;
        // Validator manager parameters
        uint256 epochDuration;
        uint256 baseChainId;
        // Stake manager parameters
        uint256 minStakeAmount;
        uint256 minWithdrawAmount;
        uint256 minUnstakeDelay;
        uint256 correctProofReward;
        uint256 incorrectProofPenalty;
        uint32 maxMissedProofs;
        uint256 slashingRate;
    }

    constructor() JsonDeploymentHandler("bridge-deployment") {}

    /// @notice Deploys all contracts on the current chain.
    /// @dev Reads deployer key from NETWORK_PRIVATE_KEY.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("NETWORK_PRIVATE_KEY");
        bytes32 programVkey = vm.envBytes32("PROGRAM_VKEY");
        address sp1Verifier = vm.envAddress("SP1_VERIFIER_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        options.unsafeAllow = "internal-function-storage";

        console.log("Deploying on chain:", block.chainid);
        console.log("Deployer:", deployer);

        ChainConfig memory cfg = _getChainConfig(block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        _deployTokens(deployer, cfg);
        _deployBridge(deployer);
        _seedBridgeLiquidity();
        _deployStakeManager(deployer, cfg);
        _deployValidatorManager(deployer, sp1Verifier, programVkey);
        _wireContracts();

        vm.stopBroadcast();

        _writeAddress("tokenA", address(tokenA));
        _writeAddress("tokenB", address(tokenB));
        _writeAddress("bridge", address(bridge));
        _writeAddress("stakeManager", address(stakeManager));
        _writeAddress("validatorManager", address(validatorManager));
        _writeDeployment();

        console.log("Deployment complete");
        console.log("  tokenA:", address(tokenA));
        console.log("  tokenB:", address(tokenB));
        console.log("  bridge:", address(bridge));
        console.log("  stakeManager:", address(stakeManager));
        console.log("  validatorManager:", address(validatorManager));
    }

    /// @notice Deploys chain-local bridge tokens and mints to deployer.
    /// @param deployer Address receiving initial token supply.
    /// @param cfg Chain configuration containing token metadata.
    function _deployTokens(address deployer, ChainConfig memory cfg) internal {
        tokenA = new BridgeToken(cfg.tokenAName, cfg.tokenASymbol);
        tokenB = new BridgeToken(cfg.tokenBName, cfg.tokenBSymbol);

        tokenA.mint(deployer, DEFAULT_TOKEN_SUPPLY);
        tokenB.mint(deployer, DEFAULT_TOKEN_SUPPLY);
    }

    /// @notice Deploys Bridge as a UUPS proxy and initializes it.
    /// @param deployer Owner passed into Bridge.initialize.
    function _deployBridge(address deployer) internal {
        address proxy = Upgrades.deployUUPSProxy(
            "Bridge.sol", abi.encodeCall(Bridge.initialize, (deployer)), options
        );
        bridge = Bridge(payable(proxy));
    }

    /// @notice Seeds the bridge with chain-local liquidity for claims.
    /// @dev Local development uses prefunded bridge balances instead of external market makers.
    function _seedBridgeLiquidity() internal {
        tokenA.mint(address(bridge), DEFAULT_BRIDGE_LIQUIDITY_SUPPLY);
        tokenB.mint(address(bridge), DEFAULT_BRIDGE_LIQUIDITY_SUPPLY);

        (bool success,) =
            payable(address(bridge)).call{value: DEFAULT_NATIVE_BRIDGE_LIQUIDITY_SUPPLY}("");
        require(success, "Bridge native liquidity funding failed");
    }

    /// @notice Deploys StakeManager as a UUPS proxy and initializes it.
    /// @param deployer Owner address used for initialization.
    /// @param cfg Chain configuration containing staking parameters.
    function _deployStakeManager(address deployer, ChainConfig memory cfg) internal {
        IStakeManagerTypes.StakeManagerConfig memory stakeCfg = IStakeManagerTypes
            .StakeManagerConfig({
            minStakeAmount: cfg.minStakeAmount,
            minWithdrawAmount: cfg.minWithdrawAmount,
            minUnstakeDelay: cfg.minUnstakeDelay,
            correctProofReward: cfg.correctProofReward,
            incorrectProofPenalty: cfg.incorrectProofPenalty,
            maxMissedProofs: cfg.maxMissedProofs,
            slashingRate: cfg.slashingRate,
            stakingToken: address(tokenA)
        });

        address proxy = Upgrades.deployUUPSProxy(
            "StakeManager.sol",
            abi.encodeCall(StakeManager.initialize, (stakeCfg, deployer)),
            options
        );

        stakeManager = StakeManager(proxy);
    }

    /// @notice Deploys ValidatorManager as a UUPS proxy and initializes it.
    /// @param deployer Owner address used for initialization.
    /// @param sp1Verifier SP1 verifier contract deployed on the target chain.
    /// @param programVkey SP1 verification key derived from the bridge program ELF.
    function _deployValidatorManager(
        address deployer,
        address sp1Verifier,
        bytes32 programVkey
    ) internal {
        address proxy = Upgrades.deployUUPSProxy(
            "ValidatorManager.sol",
            abi.encodeCall(ValidatorManager.initialize, (deployer, sp1Verifier, programVkey)),
            options
        );

        validatorManager = ValidatorManager(proxy);
    }

    /// @notice Wires the freshly deployed contracts together.
    /// @dev Every bridge points at its local validator manager. Only the base chain wires
    /// StakeManager and ValidatorManager together so settlement remains hub-only.
    function _wireContracts() internal {
        bridge.updateValidatorManager(address(validatorManager));

        if (block.chainid == BASE_CHAIN) {
            stakeManager.updateValidatorManager(address(validatorManager));
            validatorManager.updateStakingManager(address(stakeManager));
        }
    }

    /// @notice Returns the deployment configuration for a chain.
    /// @dev Values are hard-coded to keep deployments deterministic.
    /// @param chainId Current EVM chain id.
    function _getChainConfig(uint256 chainId) internal pure returns (ChainConfig memory) {
        if (chainId == 31338) {
            return ChainConfig({
                tokenAName: "Ethereum Bridge Token A",
                tokenASymbol: "EBTA",
                tokenBName: "Ethereum Bridge Token B",
                tokenBSymbol: "EBTB",
                nodeManager: address(0),
                epochDuration: 1 days,
                baseChainId: 31339,
                minStakeAmount: 200 ether,
                minWithdrawAmount: 1 ether,
                minUnstakeDelay: 7 days,
                correctProofReward: 1 ether,
                incorrectProofPenalty: 1 ether,
                maxMissedProofs: 3,
                slashingRate: 10
            });
        }

        if (chainId == 31339) {
            return ChainConfig({
                tokenAName: "Base Bridge Token A",
                tokenASymbol: "BBTA",
                tokenBName: "Base Bridge Token B",
                tokenBSymbol: "BBTB",
                nodeManager: address(0),
                epochDuration: 1 days,
                baseChainId: 31339,
                minStakeAmount: 200 ether,
                minWithdrawAmount: 1 ether,
                minUnstakeDelay: 7 days,
                correctProofReward: 1 ether,
                incorrectProofPenalty: 1 ether,
                maxMissedProofs: 3,
                slashingRate: 10
            });
        }

        string memory chainIdStr = chainId.toString();
        return ChainConfig({
            tokenAName: string(abi.encodePacked("Bridge Token A Chain ", chainIdStr)),
            tokenASymbol: string(abi.encodePacked("BTA", chainIdStr)),
            tokenBName: string(abi.encodePacked("Bridge Token B Chain ", chainIdStr)),
            tokenBSymbol: string(abi.encodePacked("BTB", chainIdStr)),
            nodeManager: address(0),
            epochDuration: 1 days,
            baseChainId: 31339,
            minStakeAmount: 200 ether,
            minWithdrawAmount: 1 ether,
            minUnstakeDelay: 7 days,
            correctProofReward: 1 ether,
            incorrectProofPenalty: 1 ether,
            maxMissedProofs: 3,
            slashingRate: 10
        });
    }
}
