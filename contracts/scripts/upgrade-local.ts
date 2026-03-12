import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import {
  Address,
  createPublicClient,
  createWalletClient,
  defineChain,
  getAddress,
  Hex,
  http,
  parseAbi,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

type ApplicationArguments = {
  chainId: number;
  rpcUrl: string;
  deploymentFilePath: string;
};

type DeploymentAddresses = {
  chainId: number;
  chainName: string;
  stakeManager: Address;
  validatorManager: Address;
};

type CompiledArtifact = {
  abi: readonly unknown[];
  bytecode: {
    object: string;
  };
};

type ChainClients = ReturnType<typeof createChainClients>;

type UpgradeResult = {
  proxy: Address;
  previousImplementation: Address;
  newImplementation: Address;
  upgradeTransactionHash: Hex;
};

const implementationSlot =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc" as const;
const upgradeableAbi = parseAbi([
  "function owner() view returns (address)",
  "function upgradeToAndCall(address newImplementation, bytes data) external",
]);
const stakeManagerArtifact = loadArtifact("out/StakeManager.sol/StakeManager.json");
const validatorManagerArtifact = loadArtifact("out/ValidatorManager.sol/ValidatorManager.json");

async function main(): Promise<void> {
  const applicationArguments = parseApplicationArguments(process.argv.slice(2));
  const ownerPrivateKey = readEnvironmentVariable("NETWORK_PRIVATE_KEY") as Hex;
  const account = privateKeyToAccount(ownerPrivateKey);
  const chainClients = createChainClients(
    applicationArguments.chainId,
    applicationArguments.rpcUrl,
    account,
  );
  const deployments = loadDeployments(applicationArguments.deploymentFilePath);

  const stakeManagerUpgrade = await upgradeProxy(
    chainClients,
    deployments.stakeManager,
    stakeManagerArtifact,
    "StakeManager",
  );
  const validatorManagerUpgrade = await upgradeProxy(
    chainClients,
    deployments.validatorManager,
    validatorManagerArtifact,
    "ValidatorManager",
  );

  console.log(
    JSON.stringify(
      {
        chainId: applicationArguments.chainId,
        rpcUrl: applicationArguments.rpcUrl,
        deploymentFilePath: applicationArguments.deploymentFilePath,
        upgrades: {
          stakeManager: stakeManagerUpgrade,
          validatorManager: validatorManagerUpgrade,
        },
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
        "expected arguments in the form --chain-id <value> --rpc-url <value> --deployment-file <value>",
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

  const deploymentFilePath = argumentsByName.get("--deployment-file");
  if (!deploymentFilePath) {
    throw new Error("missing --deployment-file");
  }

  return { chainId, rpcUrl, deploymentFilePath };
}

function readEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`missing ${name}`);
  }

  return value;
}

function createChainClients(
  chainId: number,
  rpcUrl: string,
  account: ReturnType<typeof privateKeyToAccount>,
) {
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

function loadDeployments(deploymentFilePath: string): DeploymentAddresses {
  const resolvedPath = path.resolve(process.cwd(), deploymentFilePath);
  return JSON.parse(fs.readFileSync(resolvedPath, "utf8")) as DeploymentAddresses;
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

async function upgradeProxy(
  chainClients: ChainClients,
  proxy: Address,
  artifact: CompiledArtifact,
  contractName: string,
): Promise<UpgradeResult> {
  await ensureContractCode(chainClients, proxy, `${contractName} proxy`);
  const owner = await chainClients.publicClient.readContract({
    address: proxy,
    abi: upgradeableAbi,
    functionName: "owner",
  });
  if (getAddress(owner) !== chainClients.account.address) {
    throw new Error(
      `${contractName} proxy owner ${owner} does not match upgrade signer ${chainClients.account.address}`,
    );
  }

  const previousImplementation = await readImplementationAddress(chainClients, proxy);
  const newImplementation = await deployArtifact(chainClients, artifact);
  const upgradeTransactionHash = await chainClients.walletClient.writeContract({
    address: proxy,
    abi: upgradeableAbi,
    functionName: "upgradeToAndCall",
    args: [newImplementation, "0x"],
    account: chainClients.account,
    chain: chainClients.chain,
  });
  const upgradeReceipt = await chainClients.publicClient.waitForTransactionReceipt({
    hash: upgradeTransactionHash,
  });
  if (upgradeReceipt.status !== "success") {
    throw new Error(
      `${contractName} upgrade transaction ${upgradeTransactionHash} reverted for proxy ${proxy}`,
    );
  }

  const implementationAfterUpgrade = await readImplementationAddress(chainClients, proxy);
  if (getAddress(implementationAfterUpgrade) !== getAddress(newImplementation)) {
    throw new Error(
      `${contractName} proxy ${proxy} still points to ${implementationAfterUpgrade} after upgrade tx ${upgradeTransactionHash}; expected ${newImplementation}`,
    );
  }

  return {
    proxy,
    previousImplementation,
    newImplementation,
    upgradeTransactionHash,
  };
}

async function deployArtifact(
  chainClients: ChainClients,
  artifact: CompiledArtifact,
): Promise<Address> {
  const transactionHash = await chainClients.walletClient.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode.object as Hex,
    args: [],
    account: chainClients.account,
    chain: chainClients.chain,
  });
  const receipt = await chainClients.publicClient.waitForTransactionReceipt({ hash: transactionHash });

  if (!receipt.contractAddress) {
    throw new Error(`deployment transaction ${transactionHash} did not create a contract`);
  }

  return getAddress(receipt.contractAddress);
}

async function readImplementationAddress(
  chainClients: ChainClients,
  proxy: Address,
): Promise<Address> {
  const rawValue = await chainClients.publicClient.getStorageAt({
    address: proxy,
    slot: implementationSlot,
  });
  if (!rawValue || rawValue === "0x") {
    throw new Error(`failed to read implementation slot for proxy ${proxy}`);
  }

  return getAddress(`0x${rawValue.slice(-40)}`);
}

async function ensureContractCode(
  chainClients: ChainClients,
  address: Address,
  contractName: string,
): Promise<void> {
  const bytecode = await chainClients.publicClient.getBytecode({ address });
  if (!bytecode || bytecode === "0x") {
    throw new Error(`${contractName} is missing on chain ${chainClients.chain.id} at ${address}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
