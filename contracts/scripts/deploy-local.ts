import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import {
  Address,
  createPublicClient,
  createWalletClient,
  defineChain,
  encodeFunctionData,
  getAddress,
  Hex,
  http,
  parseEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const baseChainId = 31339;

type ApplicationArguments = {
  chainId: number;
  rpcUrl: string;
  runtimeConfigPath: string;
  deploymentsDirectory: string;
};

type ChainDeploymentConfiguration = {
  chainName: string;
  tokenAName: string;
  tokenASymbol: string;
  tokenBName: string;
  tokenBSymbol: string;
  tokenAInitialSupply: bigint;
  tokenABridgeLiquidity: bigint;
  tokenBInitialSupply: bigint;
  tokenBBridgeLiquidity: bigint;
  nativeBridgeLiquidity: bigint;
  minStakeAmount: bigint;
  minWithdrawAmount: bigint;
  minUnstakeDelay: bigint;
  correctProofReward: bigint;
  incorrectProofPenalty: bigint;
  maxMissedProofs: number;
  slashingRate: bigint;
  sp1VerifierAddress: Address;
};

type RuntimeConfig = {
  base_chain_id: number;
  chains: RuntimeChainConfiguration[];
};

type RuntimeChainConfiguration = {
  id: number;
  name: string;
  deployment: {
    bridge: {
      native_liquidity_wei: string;
    };
    token_a: {
      name: string;
      symbol: string;
      initial_supply_wei: string;
      bridge_liquidity_wei: string;
    };
    token_b: {
      name: string;
      symbol: string;
      initial_supply_wei: string;
      bridge_liquidity_wei: string;
    };
    stake_manager: {
      min_stake_amount_wei: string;
      min_withdraw_amount_wei: string;
      min_unstake_delay_seconds: number;
      correct_proof_reward_wei: string;
      incorrect_proof_penalty_wei: string;
      max_missed_proofs: number;
      slashing_rate: number;
    };
    validator_manager: {
      deploy: boolean;
      sp1_verifier_address?: string;
    };
  };
};

type ContractDeploymentAddresses = {
  chainId: number;
  chainName: string;
  bridge: `0x${string}`;
  stakeManager: `0x${string}`;
  tokenA: `0x${string}`;
  tokenAName: string;
  tokenASymbol: string;
  tokenB: `0x${string}`;
  tokenBName: string;
  tokenBSymbol: string;
  validatorManager: `0x${string}`;
  sp1Verifier: Address;
  programVkey: Hex;
};

type CompiledArtifact = {
  abi: readonly unknown[];
  bytecode: {
    object: string;
  };
};

type ChainClients = ReturnType<typeof createChainClients>;

const bridgeArtifact = loadArtifact("out/Bridge.sol/Bridge.json");
const bridgeTokenArtifact = loadArtifact("out/BridgeToken.sol/BridgeToken.json");
const erc1967ProxyArtifact = loadArtifact("out/ERC1967Proxy.sol/ERC1967Proxy.json");
const stakeManagerArtifact = loadArtifact("out/StakeManager.sol/StakeManager.json");
const validatorManagerArtifact = loadArtifact("out/ValidatorManager.sol/ValidatorManager.json");

async function main(): Promise<void> {
  const applicationArguments = parseApplicationArguments(process.argv.slice(2));
  const chainDeploymentConfiguration = loadChainDeploymentConfiguration(
    applicationArguments.runtimeConfigPath,
    applicationArguments.chainId,
  );
  const ownerPrivateKey = readEnvironmentVariable("NETWORK_PRIVATE_KEY");
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY?.trim() || ownerPrivateKey;
  const programVerificationKey = readEnvironmentVariable("PROGRAM_VKEY") as Hex;
  const ownerAccount = privateKeyToAccount(ownerPrivateKey as Hex);
  const deployerAccount = privateKeyToAccount(deployerPrivateKey as Hex);
  const ownerChainClients = createChainClients(
    applicationArguments.chainId,
    applicationArguments.rpcUrl,
    ownerAccount,
  );
  const deployerChainClients = createChainClients(
    applicationArguments.chainId,
    applicationArguments.rpcUrl,
    deployerAccount,
  );

  await ensureDeployerFunding(
    ownerChainClients,
    deployerChainClients,
    chainDeploymentConfiguration,
  );

  const deploymentAddresses = await deployContracts(
    deployerChainClients,
    ownerChainClients,
    chainDeploymentConfiguration,
    ownerAccount.address,
    programVerificationKey,
  );

  await writeDeploymentArtifact(
    applicationArguments.deploymentsDirectory,
    applicationArguments.chainId,
    deploymentAddresses,
  );

  console.log(
    JSON.stringify(
      {
        chainId: applicationArguments.chainId,
        rpcUrl: applicationArguments.rpcUrl,
        runtimeConfigPath: applicationArguments.runtimeConfigPath,
        deployments: deploymentAddresses,
      },
      null,
      2,
    ),
  );
}

function parseApplicationArguments(rawArguments: string[]): ApplicationArguments {
  const argumentsByName = new Map<string, string>();

  for (let index = 0; index < rawArguments.length; index += 2) {
    const optionName = rawArguments[index];
    const optionValue = rawArguments[index + 1];

    if (!optionName?.startsWith("--") || !optionValue) {
      throw new Error(
        "expected arguments in the form --chain-id <value> --rpc-url <value> --runtime-config <value> [--deployments-dir <value>]",
      );
    }

    argumentsByName.set(optionName, optionValue);
  }

  const chainId = Number(argumentsByName.get("--chain-id"));
  if (!Number.isInteger(chainId) || chainId <= 0) {
    throw new Error("invalid --chain-id");
  }

  const rpcUrl = argumentsByName.get("--rpc-url");
  if (!rpcUrl) {
    throw new Error("missing --rpc-url");
  }

  const runtimeConfigPath = argumentsByName.get("--runtime-config");
  if (!runtimeConfigPath) {
    throw new Error("missing --runtime-config");
  }

  return {
    chainId,
    rpcUrl,
    runtimeConfigPath,
    deploymentsDirectory: argumentsByName.get("--deployments-dir") ?? "deploy-out",
  };
}

function readEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`missing ${name}`);
  }

  return value;
}

function createChainClients(chainId: number, rpcUrl: string, account: ReturnType<typeof privateKeyToAccount>) {
  const chain = defineChain({
    id: chainId,
    name: `local-${chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: {
      default: { http: [rpcUrl] },
      public: { http: [rpcUrl] },
    },
    blockExplorers: {
      default: { name: "local", url: rpcUrl },
    },
  });

  return {
    account,
    chain,
    publicClient: createPublicClient({ chain, transport: http(rpcUrl) }),
    walletClient: createWalletClient({ account, chain, transport: http(rpcUrl) }),
  };
}

function loadChainDeploymentConfiguration(
  runtimeConfigPath: string,
  chainId: number,
): ChainDeploymentConfiguration {
  const resolvedRuntimeConfigPath = path.resolve(process.cwd(), runtimeConfigPath);
  const runtimeConfig = JSON.parse(
    fs.readFileSync(resolvedRuntimeConfigPath, "utf8"),
  ) as RuntimeConfig;
  const chainConfiguration = runtimeConfig.chains.find((chain) => chain.id === chainId);

  if (!chainConfiguration) {
    throw new Error(`chain ${chainId} is not present in ${resolvedRuntimeConfigPath}`);
  }

  if (!chainConfiguration.deployment.validator_manager.deploy) {
    throw new Error(`chain ${chainId} disables validator_manager deployment; this stack requires it`);
  }

  return {
    chainName: chainConfiguration.name,
    tokenAName: chainConfiguration.deployment.token_a.name,
    tokenASymbol: chainConfiguration.deployment.token_a.symbol,
    tokenBName: chainConfiguration.deployment.token_b.name,
    tokenBSymbol: chainConfiguration.deployment.token_b.symbol,
    tokenAInitialSupply: BigInt(chainConfiguration.deployment.token_a.initial_supply_wei),
    tokenABridgeLiquidity: BigInt(chainConfiguration.deployment.token_a.bridge_liquidity_wei),
    tokenBInitialSupply: BigInt(chainConfiguration.deployment.token_b.initial_supply_wei),
    tokenBBridgeLiquidity: BigInt(chainConfiguration.deployment.token_b.bridge_liquidity_wei),
    nativeBridgeLiquidity: BigInt(chainConfiguration.deployment.bridge.native_liquidity_wei),
    minStakeAmount: BigInt(chainConfiguration.deployment.stake_manager.min_stake_amount_wei),
    minWithdrawAmount: BigInt(chainConfiguration.deployment.stake_manager.min_withdraw_amount_wei),
    minUnstakeDelay: BigInt(chainConfiguration.deployment.stake_manager.min_unstake_delay_seconds),
    correctProofReward: BigInt(chainConfiguration.deployment.stake_manager.correct_proof_reward_wei),
    incorrectProofPenalty: BigInt(chainConfiguration.deployment.stake_manager.incorrect_proof_penalty_wei),
    maxMissedProofs: chainConfiguration.deployment.stake_manager.max_missed_proofs,
    slashingRate: BigInt(chainConfiguration.deployment.stake_manager.slashing_rate),
    sp1VerifierAddress: resolveSp1VerifierAddress(chainConfiguration),
  };
}

function resolveSp1VerifierAddress(chainConfiguration: RuntimeChainConfiguration): Address {
  const overrideAddress = process.env.SP1_VERIFIER_ADDRESS?.trim();
  const configuredAddress = chainConfiguration.deployment.validator_manager.sp1_verifier_address?.trim();
  const verifierAddress = overrideAddress || configuredAddress;

  if (!verifierAddress || !/^0x[a-fA-F0-9]{40}$/.test(verifierAddress)) {
    throw new Error(
      `missing valid SP1 verifier address for chain ${chainConfiguration.id}; set SP1_VERIFIER_ADDRESS or configure deployment.validator_manager.sp1_verifier_address`,
    );
  }

  return getAddress(verifierAddress);
}

function loadArtifact(relativePath: string): CompiledArtifact {
  const artifactPath = path.resolve(process.cwd(), relativePath);
  const rawArtifact = fs.readFileSync(artifactPath, "utf8");
  const artifact = JSON.parse(rawArtifact) as CompiledArtifact;

  if (!artifact.bytecode?.object || artifact.bytecode.object === "0x") {
    throw new Error(`artifact ${relativePath} is missing deployable bytecode`);
  }

  return artifact;
}

async function deployContracts(
  deployerChainClients: ChainClients,
  ownerChainClients: ChainClients,
  chainDeploymentConfiguration: ChainDeploymentConfiguration,
  ownerAddress: `0x${string}`,
  programVerificationKey: Hex,
): Promise<ContractDeploymentAddresses> {
  if (deployerChainClients.chain.id === baseChainId) {
    await ensureExternalContractCode(
      deployerChainClients,
      chainDeploymentConfiguration.sp1VerifierAddress,
      "sp1Verifier",
    );
  }

  const tokenA = await deployArtifact(
    deployerChainClients,
    bridgeTokenArtifact,
    [chainDeploymentConfiguration.tokenAName, chainDeploymentConfiguration.tokenASymbol],
  );
  const tokenB = await deployArtifact(
    deployerChainClients,
    bridgeTokenArtifact,
    [chainDeploymentConfiguration.tokenBName, chainDeploymentConfiguration.tokenBSymbol],
  );

  await writeContract(
    deployerChainClients,
    tokenA,
    bridgeTokenArtifact.abi,
    "mint",
    [ownerAddress, chainDeploymentConfiguration.tokenAInitialSupply],
  );
  await writeContract(
    deployerChainClients,
    tokenB,
    bridgeTokenArtifact.abi,
    "mint",
    [ownerAddress, chainDeploymentConfiguration.tokenBInitialSupply],
  );

  const bridgeImplementation = await deployArtifact(deployerChainClients, bridgeArtifact, []);
  const bridgeInitialization = encodeFunctionData({
    abi: bridgeArtifact.abi,
    functionName: "initialize",
    args: [ownerAddress],
  });
  const bridge = await deployArtifact(deployerChainClients, erc1967ProxyArtifact, [
    bridgeImplementation,
    bridgeInitialization,
  ]);

  const stakeManagerImplementation = await deployArtifact(deployerChainClients, stakeManagerArtifact, []);
  const stakeManagerInitialization = encodeFunctionData({
    abi: stakeManagerArtifact.abi,
    functionName: "initialize",
    args: [
      {
        minStakeAmount: chainDeploymentConfiguration.minStakeAmount,
        minWithdrawAmount: chainDeploymentConfiguration.minWithdrawAmount,
        minUnstakeDelay: chainDeploymentConfiguration.minUnstakeDelay,
        correctProofReward: chainDeploymentConfiguration.correctProofReward,
        incorrectProofPenalty: chainDeploymentConfiguration.incorrectProofPenalty,
        maxMissedProofs: chainDeploymentConfiguration.maxMissedProofs,
        slashingRate: chainDeploymentConfiguration.slashingRate,
        stakingToken: tokenA,
      },
      ownerAddress,
    ],
  });
  const stakeManager = await deployArtifact(deployerChainClients, erc1967ProxyArtifact, [
    stakeManagerImplementation,
    stakeManagerInitialization,
  ]);

  const validatorManagerImplementation = await deployArtifact(
    deployerChainClients,
    validatorManagerArtifact,
    [],
  );
  const validatorManagerInitialization = encodeFunctionData({
    abi: validatorManagerArtifact.abi,
    functionName: "initialize",
    args: [ownerAddress, chainDeploymentConfiguration.sp1VerifierAddress, programVerificationKey],
  });
  const validatorManager = await deployArtifact(deployerChainClients, erc1967ProxyArtifact, [
    validatorManagerImplementation,
    validatorManagerInitialization,
  ]);

  await writeContract(
    deployerChainClients,
    tokenA,
    bridgeTokenArtifact.abi,
    "mint",
    [bridge, chainDeploymentConfiguration.tokenABridgeLiquidity],
  );
  await writeContract(
    deployerChainClients,
    tokenB,
    bridgeTokenArtifact.abi,
    "mint",
    [bridge, chainDeploymentConfiguration.tokenBBridgeLiquidity],
  );
  await sendEther(deployerChainClients, bridge, chainDeploymentConfiguration.nativeBridgeLiquidity);

  await writeContract(
    ownerChainClients,
    bridge,
    bridgeArtifact.abi,
    "updateValidatorManager",
    [validatorManager],
  );

  if (deployerChainClients.chain.id === baseChainId) {
    await writeContract(
      ownerChainClients,
      stakeManager,
      stakeManagerArtifact.abi,
      "updateValidatorManager",
      [validatorManager],
    );
    await writeContract(
      ownerChainClients,
      validatorManager,
      validatorManagerArtifact.abi,
      "updateStakingManager",
      [stakeManager],
    );
  }

  await ensureContractCode(deployerChainClients, bridge, "bridge");
  await ensureContractCode(deployerChainClients, stakeManager, "stakeManager");
  await ensureContractCode(deployerChainClients, validatorManager, "validatorManager");

  return {
    chainId: deployerChainClients.chain.id,
    chainName: chainDeploymentConfiguration.chainName,
    bridge: getAddress(bridge),
    stakeManager: getAddress(stakeManager),
    tokenA: getAddress(tokenA),
    tokenAName: chainDeploymentConfiguration.tokenAName,
    tokenASymbol: chainDeploymentConfiguration.tokenASymbol,
    tokenB: getAddress(tokenB),
    tokenBName: chainDeploymentConfiguration.tokenBName,
    tokenBSymbol: chainDeploymentConfiguration.tokenBSymbol,
    validatorManager: getAddress(validatorManager),
    sp1Verifier: chainDeploymentConfiguration.sp1VerifierAddress,
    programVkey: programVerificationKey,
  };
}

async function ensureDeployerFunding(
  ownerChainClients: ChainClients,
  deployerChainClients: ChainClients,
  chainDeploymentConfiguration: ChainDeploymentConfiguration,
): Promise<void> {
  if (ownerChainClients.account.address === deployerChainClients.account.address) {
    return;
  }

  const requiredDeployerBalance =
    chainDeploymentConfiguration.nativeBridgeLiquidity + parseEther("250");
  const deployerBalance = await deployerChainClients.publicClient.getBalance({
    address: deployerChainClients.account.address,
  });

  if (deployerBalance >= requiredDeployerBalance) {
    return;
  }

  const transactionHash = await ownerChainClients.walletClient.sendTransaction({
    account: ownerChainClients.account,
    chain: ownerChainClients.chain,
    to: deployerChainClients.account.address,
    value: requiredDeployerBalance - deployerBalance,
  });

  await ownerChainClients.publicClient.waitForTransactionReceipt({ hash: transactionHash });
}

async function deployArtifact(
  chainClients: ChainClients,
  artifact: CompiledArtifact,
  constructorArguments: readonly unknown[],
): Promise<`0x${string}`> {
  const transactionHash = await chainClients.walletClient.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode.object as Hex,
    args: constructorArguments,
    account: chainClients.account,
    chain: chainClients.chain,
  });
  const receipt = await chainClients.publicClient.waitForTransactionReceipt({ hash: transactionHash });

  if (!receipt.contractAddress) {
    throw new Error(`deployment transaction ${transactionHash} did not create a contract`);
  }

  return receipt.contractAddress;
}

async function writeContract(
  chainClients: ChainClients,
  address: `0x${string}`,
  abi: readonly unknown[],
  functionName: string,
  functionArguments: readonly unknown[],
): Promise<void> {
  const transactionHash = await chainClients.walletClient.writeContract({
    address,
    abi,
    functionName,
    args: functionArguments,
    account: chainClients.account,
    chain: chainClients.chain,
  });

  await chainClients.publicClient.waitForTransactionReceipt({ hash: transactionHash });
}

async function sendEther(
  chainClients: ChainClients,
  address: `0x${string}`,
  value: bigint,
): Promise<void> {
  const transactionHash = await chainClients.walletClient.sendTransaction({
    to: address,
    value,
    account: chainClients.account,
    chain: chainClients.chain,
  });

  await chainClients.publicClient.waitForTransactionReceipt({ hash: transactionHash });
}

async function ensureContractCode(
  chainClients: ChainClients,
  address: `0x${string}`,
  contractName: string,
): Promise<void> {
  const bytecode = await chainClients.publicClient.getBytecode({ address });
  if (!bytecode || bytecode === "0x") {
    throw new Error(
      `${contractName} deployment verification failed on chain ${chainClients.chain.id} at ${address}`,
    );
  }
}

async function ensureExternalContractCode(
  chainClients: ChainClients,
  address: Address,
  contractName: string,
): Promise<void> {
  const bytecode = await chainClients.publicClient.getBytecode({ address });
  if (!bytecode || bytecode === "0x") {
    throw new Error(
      `${contractName} is missing on chain ${chainClients.chain.id} at ${address}; verify the fork source or SP1_VERIFIER_ADDRESS`,
    );
  }
}

async function writeDeploymentArtifact(
  deploymentsDirectory: string,
  chainId: number,
  deploymentAddresses: ContractDeploymentAddresses,
): Promise<void> {
  const deploymentDirectoryPath = path.resolve(process.cwd(), deploymentsDirectory);
  fs.mkdirSync(deploymentDirectoryPath, { recursive: true });

  const deploymentPath = path.join(deploymentDirectoryPath, `${chainId}.json`);
  fs.writeFileSync(deploymentPath, `${JSON.stringify(deploymentAddresses, null, 2)}\n`);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
