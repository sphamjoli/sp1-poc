import fs from "node:fs";
import path from "node:path";
import {
  loadRuntimeConfig,
  renderRuntimeConfig,
  runtimeConfigPath,
  runtimeTemplateConfigPath,
  type RuntimeChainConfig,
  type RuntimeConfig,
} from "./runtime-config-lib.ts";
import { updateIndexerConfig } from "./update-indexer-config.ts";

type Command = "update" | "remove";

type DeployAddresses = {
  chainId?: number;
  chainName?: string;
  bridge: `0x${string}`;
  stakeManager: `0x${string}`;
  tokenA: `0x${string}`;
  tokenAName?: string;
  tokenASymbol?: string;
  tokenB: `0x${string}`;
  tokenBName?: string;
  tokenBSymbol?: string;
  validatorManager: `0x${string}`;
};

type GeneratedChain = {
  id: number;
  name: string;
  rpcUrl: string;
  bridge: `0x${string}`;
  validatorManager: `0x${string}`;
};

const supportedChainsDirectory = path.join("config", "chains");
const unsupportedChainsDirectory = path.join("config", "unsupported");
const uiGeneratedConfigPath = path.join("apps", "web", "src", "generated", "bridgeConfig.ts");
const indexerGeneratedConfigPath = path.join("indexer", "src", "generated", "chainMetadata.ts");
const swapSpender = "0x1111111111111111111111111111111111111111";
const nativeTokenAddress = "0x0000000000000000000000000000000000000000";

function readDeployAddresses(runtimeConfig: RuntimeConfig, chainId: number): DeployAddresses {
  const deployPath = path.join(runtimeConfig.deployments_dir, `${chainId}.json`);
  if (!fs.existsSync(deployPath)) {
    throw new Error(`${deployPath} not found - run \`make deploy-local\` before \`make update-chains\``);
  }

  const parsed = JSON.parse(fs.readFileSync(deployPath, "utf8")) as Partial<DeployAddresses>;
  if (!parsed.bridge || !parsed.validatorManager || !parsed.tokenA || !parsed.tokenB) {
    throw new Error(`missing deploy addresses in ${deployPath}`);
  }

  return parsed as DeployAddresses;
}

function tokenName(chain: RuntimeChainConfig, deploy: DeployAddresses, tokenSide: "A" | "B"): string {
  if (tokenSide === "A") {
    return chain.deployment.token_a.name || deploy.tokenAName || `${chain.name} Bridge Token A`;
  }

  return chain.deployment.token_b.name || deploy.tokenBName || `${chain.name} Bridge Token B`;
}

function tokenSymbol(chain: RuntimeChainConfig, deploy: DeployAddresses, tokenSide: "A" | "B"): string {
  if (tokenSide === "A") {
    return chain.deployment.token_a.symbol || deploy.tokenASymbol || `BTA${chain.id}`;
  }

  return chain.deployment.token_b.symbol || deploy.tokenBSymbol || `BTB${chain.id}`;
}

function nativeTokenName(chain: RuntimeChainConfig): string {
  return `${chain.name} Native Ether`;
}

function nativeTokenSymbol(): string {
  return "ETH";
}

function serializeUiChains(runtimeConfig: RuntimeConfig): string {
  const generatedChains: GeneratedChain[] = runtimeConfig.chains.map((chain) => {
    const deploy = readDeployAddresses(runtimeConfig, chain.id);
    return {
      id: chain.id,
      name: chain.name,
      rpcUrl: chain.rpc_url,
      bridge: deploy.bridge,
      validatorManager: deploy.validatorManager,
    };
  });

  const supportedTokens = runtimeConfig.chains.flatMap((chain) => {
    const deploy = readDeployAddresses(runtimeConfig, chain.id);
    return [
      {
        chainId: chain.id,
        address: nativeTokenAddress,
        symbol: nativeTokenSymbol(),
        name: nativeTokenName(chain),
        decimals: 18,
        isNative: true,
      },
      {
        chainId: chain.id,
        address: deploy.tokenA,
        symbol: tokenSymbol(chain, deploy, "A"),
        name: tokenName(chain, deploy, "A"),
        decimals: 18,
        isNative: false,
      },
      {
        chainId: chain.id,
        address: deploy.tokenB,
        symbol: tokenSymbol(chain, deploy, "B"),
        name: tokenName(chain, deploy, "B"),
        decimals: 18,
        isNative: false,
      },
    ];
  });

  const defaultChainId = runtimeConfig.chains.some((chain) => chain.id === 1)
    ? 1
    : runtimeConfig.chains[0]?.id ?? runtimeConfig.base_chain_id;

  const chainLabels = Object.fromEntries(runtimeConfig.chains.map((chain) => [chain.id, chain.name]));

  return `import type { TokenInfo } from "@/types/swap";

export interface SupportedChain {
  id: number;
  name: string;
  rpcUrl: string;
  bridge: \`0x\${string}\`;
  validatorManager: \`0x\${string}\`;
}

export const SUPPORTED_CHAINS: SupportedChain[] = ${JSON.stringify(generatedChains, null, 2)} as SupportedChain[];

export const CHAIN_LABELS: Record<number, string> = ${JSON.stringify(chainLabels, null, 2)};

export const SUPPORTED_TOKENS: TokenInfo[] = ${JSON.stringify(supportedTokens, null, 2)} as TokenInfo[];

export const DEFAULT_CHAIN_ID = ${defaultChainId};

export const SWAP_SPENDER: \`0x\${string}\` = "${swapSpender}";
`;
}

function serializeIndexerChains(runtimeConfig: RuntimeConfig): string {
  const chainLabels = Object.fromEntries(runtimeConfig.chains.map((chain) => [chain.id, chain.name]));

  return `export const CHAIN_NAMES: Record<number, string> = ${JSON.stringify(chainLabels, null, 2)};

export function chainName(chainId: number): string {
  return CHAIN_NAMES[chainId] ?? \`Chain \${chainId}\`;
}
`;
}

function writeFile(outputPath: string, contents: string): void {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${contents.trimEnd()}\n`, "utf8");
}

function chainIdsFromDirectory(directoryPath: string): number[] {
  if (!fs.existsSync(directoryPath)) {
    return [];
  }

  return fs
    .readdirSync(directoryPath, { withFileTypes: true })
    .filter((directoryEntry) => directoryEntry.isDirectory())
    .map((directoryEntry) => {
      const chainId = Number.parseInt(directoryEntry.name, 10);
      if (!Number.isInteger(chainId) || chainId <= 0) {
        throw new Error(`invalid chain directory ${path.join(directoryPath, directoryEntry.name)}`);
      }
      return chainId;
    })
    .sort((left, right) => left - right);
}

function removeUnsupportedChains(): number[] {
  const runtimeConfig = loadRuntimeConfig(runtimeConfigPath());
  const removedChainIds: number[] = [];
  for (const chainId of chainIdsFromDirectory(unsupportedChainsDirectory)) {
    const supportedDirectory = path.join(supportedChainsDirectory, String(chainId));
    if (fs.existsSync(supportedDirectory)) {
      fs.rmSync(supportedDirectory, { recursive: true, force: true });
      removedChainIds.push(chainId);
    }

    const deployPath = path.join(runtimeConfig.deployments_dir, `${chainId}.json`);
    if (fs.existsSync(deployPath)) {
      fs.rmSync(deployPath, { force: true });
    }
  }

  return removedChainIds;
}

function shouldReuseRuntimeConfig(): boolean {
  return process.env.REUSE_RUNTIME_CONFIG?.trim() === "1";
}

async function synchronizeGeneratedAssets(command: Command): Promise<void> {
  fs.mkdirSync(unsupportedChainsDirectory, { recursive: true });

  const removedChainIds = command === "remove" ? removeUnsupportedChains() : [];
  const templatePath = runtimeTemplateConfigPath();
  const outputPath = runtimeConfigPath();
  const runtimeConfig = shouldReuseRuntimeConfig() && fs.existsSync(outputPath)
    ? loadRuntimeConfig(outputPath)
    : await renderRuntimeConfig(templatePath, outputPath);

  if (!runtimeConfig.chains.some((chain) => chain.id === runtimeConfig.base_chain_id)) {
    throw new Error(
      `base chain ${runtimeConfig.base_chain_id} is not present in ${supportedChainsDirectory}`,
    );
  }

  writeFile(uiGeneratedConfigPath, serializeUiChains(runtimeConfig));
  writeFile(indexerGeneratedConfigPath, serializeIndexerChains(runtimeConfig));

  process.env.RUNTIME_CONFIG = outputPath;
  updateIndexerConfig();

  if (removedChainIds.length > 0) {
    console.log(`Removed supported chains: ${removedChainIds.join(", ")}`);
  }

  console.log(`Updated ${uiGeneratedConfigPath}`);
  console.log(`Updated ${indexerGeneratedConfigPath}`);
}

async function main(): Promise<void> {
  const command = process.argv[2] as Command | undefined;
  if (!command || (command !== "update" && command !== "remove")) {
    throw new Error("usage: node --import tsx scripts/sync-chains.ts <update|remove>");
  }

  await synchronizeGeneratedAssets(command);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
