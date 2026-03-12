import fs from "node:fs";
import path from "node:path";
import { loadRuntimeConfig, runtimeConfigPath, type RuntimeConfig } from "./runtime-config-lib.ts";

interface DeployAddresses {
  bridge?: string;
  stakeManager?: string;
  tokenA?: string;
  tokenB?: string;
  validatorManager?: string;
  sp1Verifier?: string;
  programVkey?: string;
}

interface JsonRpcSuccess<T> {
  jsonrpc: "2.0";
  id: number;
  result: T;
}

interface JsonRpcFailure {
  jsonrpc: "2.0";
  id: number;
  error: {
    code: number;
    message: string;
  };
}

function resolveConfiguredPath(configPath: string, configuredPath: string): string {
  if (path.isAbsolute(configuredPath)) {
    return configuredPath;
  }

  const workspaceCandidate = path.resolve(process.cwd(), configuredPath);
  if (fs.existsSync(workspaceCandidate)) {
    return workspaceCandidate;
  }

  return path.resolve(path.dirname(configPath), configuredPath);
}

function parseConfigPath(): string {
  const configFlagIndex = process.argv.findIndex((argument) => argument === "--config");
  if (configFlagIndex >= 0) {
    const flagValue = process.argv[configFlagIndex + 1];
    if (!flagValue) {
      throw new Error("missing value for --config");
    }

    return path.resolve(flagValue);
  }

  return path.resolve(runtimeConfigPath());
}

function loadDeployAddresses(runtimeConfig: RuntimeConfig, configPath: string, chainId: number): DeployAddresses {
  const deploymentsDirectory = resolveConfiguredPath(configPath, runtimeConfig.deployments_dir);
  const deployPath = path.join(deploymentsDirectory, `${chainId}.json`);
  if (!fs.existsSync(deployPath)) {
    throw new Error(`missing deployment artifact ${deployPath}`);
  }

  return JSON.parse(fs.readFileSync(deployPath, "utf8")) as DeployAddresses;
}

function isAddress(value: string | undefined): value is `0x${string}` {
  return Boolean(value && /^0x[a-fA-F0-9]{40}$/.test(value));
}

function isBytes32(value: string | undefined): value is `0x${string}` {
  return Boolean(value && /^0x[a-fA-F0-9]{64}$/.test(value));
}

async function rpcRequest<T>(rpcUrl: string, method: string, params: unknown[]): Promise<T> {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method,
      params,
    }),
  });

  if (!response.ok) {
    throw new Error(`rpc request to ${rpcUrl} failed with status ${response.status}`);
  }

  const payload = await response.json() as JsonRpcSuccess<T> | JsonRpcFailure;
  if ("error" in payload) {
    throw new Error(`rpc request ${method} failed: ${payload.error.message}`);
  }

  return payload.result;
}

async function assertContractCode(rpcUrl: string, label: string, address: string | undefined): Promise<void> {
  if (!isAddress(address)) {
    throw new Error(`deployment artifact has invalid ${label} address`);
  }

  const code = await rpcRequest<string>(rpcUrl, "eth_getCode", [address, "latest"]);
  if (code === "0x") {
    throw new Error(`${label} has no code at ${address}`);
  }
}

async function validateChain(runtimeConfig: RuntimeConfig, configPath: string, chainId: number): Promise<void> {
  const chain = runtimeConfig.chains.find((candidate) => candidate.id === chainId);
  if (!chain) {
    throw new Error(`runtime config does not contain chain ${chainId}`);
  }

  const deployAddresses = loadDeployAddresses(runtimeConfig, configPath, chainId);
  const reportedChainId = await rpcRequest<string>(chain.rpc_url, "eth_chainId", []);
  if (Number.parseInt(reportedChainId, 16) !== chain.id) {
    throw new Error(`rpc ${chain.rpc_url} returned chain id ${reportedChainId} instead of ${chain.id}`);
  }

  await assertContractCode(chain.rpc_url, "bridge", deployAddresses.bridge);
  await assertContractCode(chain.rpc_url, "validator manager", deployAddresses.validatorManager);
  await assertContractCode(chain.rpc_url, "token A", deployAddresses.tokenA);
  await assertContractCode(chain.rpc_url, "token B", deployAddresses.tokenB);

  if (isAddress(deployAddresses.stakeManager)) {
    await assertContractCode(chain.rpc_url, "stake manager", deployAddresses.stakeManager);
  }

  if (!isBytes32(deployAddresses.programVkey)) {
    throw new Error(`deployment artifact for chain ${chainId} is missing a valid programVkey`);
  }

  if (chain.id === runtimeConfig.base_chain_id) {
    await assertContractCode(chain.rpc_url, "sp1 verifier", deployAddresses.sp1Verifier);
  }
}

async function main(): Promise<void> {
  const configPath = parseConfigPath();
  const runtimeConfig = loadRuntimeConfig(configPath);

  for (const chain of runtimeConfig.chains) {
    await validateChain(runtimeConfig, configPath, chain.id);
  }

  console.log("runtime deployments are healthy");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
