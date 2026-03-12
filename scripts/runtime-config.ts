import {
  chainById,
  loadRuntimeConfig,
  renderRuntimeConfig,
  runtimeConfigPath,
  runtimeTemplateConfigPath,
} from "./runtime-config-lib.ts";
import fs from "node:fs";
import path from "node:path";

type Command =
  | "render"
  | "chain-ids"
  | "validator-names"
  | "chain-fork-url"
  | "chain-rpc-url"
  | "chain-port"
  | "anvil-state-interval"
  | "service-bind"
  | "service-url"
  | "ui-bind"
  | "ui-url"
  | "deployments-dir"
  | "deployment-file"
  | "deployment-address"
  | "indexer-url"
  | "indexer-port";

function argumentValue(argumentsList: string[], name: string): string | undefined {
  const index = argumentsList.indexOf(name);
  if (index < 0) {
    return undefined;
  }

  return argumentsList[index + 1];
}

function requiredArgument(argumentsList: string[], name: string): string {
  const value = argumentValue(argumentsList, name);
  if (!value) {
    throw new Error(`missing required argument ${name}`);
  }
  return value;
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

function serviceBind(
  configPath: string,
  serviceName: "chain_manager" | "node_manager",
): string {
  const runtimeConfig = loadRuntimeConfig(configPath);
  return runtimeConfig.services[serviceName].bind;
}

function serviceUrl(
  configPath: string,
  serviceName: "chain_manager" | "node_manager",
): string {
  return `http://${serviceBind(configPath, serviceName)}`;
}

function deploymentFilePath(configPath: string, chainId: number): string {
  const runtimeConfig = loadRuntimeConfig(configPath);
  const deploymentsDir = resolveConfiguredPath(configPath, runtimeConfig.deployments_dir);
  return path.resolve(deploymentsDir, `${chainId}.json`);
}

function urlPort(url: string): string {
  const parsedUrl = new URL(url);
  return parsedUrl.port || (parsedUrl.protocol === "https:" ? "443" : "80");
}

async function main(): Promise<void> {
  const [, , command, ...argumentsList] = process.argv as [string, string, Command | undefined, ...string[]];
  if (!command) {
    throw new Error("missing command");
  }

  if (command === "render") {
    const templatePath = argumentValue(argumentsList, "--template") ?? runtimeTemplateConfigPath();
    const outputPath = argumentValue(argumentsList, "--output") ?? runtimeConfigPath();
    const renderedConfig = await renderRuntimeConfig(templatePath, outputPath);
    console.log(`Rendered ${outputPath}`);
    for (const chain of renderedConfig.chains) {
      console.log(`  chain ${chain.id}: ${chain.rpc_url}`);
    }
    console.log(`  chain-manager: ${renderedConfig.services.chain_manager.bind}`);
    console.log(`  node-manager: ${renderedConfig.services.node_manager.bind}`);
    console.log(`  indexer: ${renderedConfig.indexer.hasura_url}`);
    return;
  }

  const configPath = argumentValue(argumentsList, "--config") ?? runtimeConfigPath();
  if (command === "chain-ids") {
    for (const chain of loadRuntimeConfig(configPath).chains) {
      console.log(chain.id);
    }
    return;
  }

  if (command === "validator-names") {
    const runtimeConfig = loadRuntimeConfig(configPath);
    const validatorCatalogPath = resolveConfiguredPath(configPath, runtimeConfig.validators_path);
    const validatorCatalog = JSON.parse(fs.readFileSync(validatorCatalogPath, "utf8")) as Array<{ name?: string }>;
    for (const validator of validatorCatalog) {
      if (validator.name?.trim()) {
        console.log(validator.name.trim());
      }
    }
    return;
  }

  if (command === "chain-rpc-url") {
    const chainId = Number(requiredArgument(argumentsList, "--chain-id"));
    console.log(chainById(loadRuntimeConfig(configPath), chainId).rpc_url);
    return;
  }

  if (command === "chain-fork-url") {
    const chainId = Number(requiredArgument(argumentsList, "--chain-id"));
    console.log(chainById(loadRuntimeConfig(configPath), chainId).fork_url ?? "");
    return;
  }

  if (command === "chain-port") {
    const chainId = Number(requiredArgument(argumentsList, "--chain-id"));
    console.log(urlPort(chainById(loadRuntimeConfig(configPath), chainId).rpc_url));
    return;
  }

  if (command === "anvil-state-interval") {
    console.log(loadRuntimeConfig(configPath).services.anvil.state_interval_secs);
    return;
  }

  if (command === "service-bind") {
    const serviceName = requiredArgument(argumentsList, "--service") as "chain_manager" | "node_manager";
    console.log(serviceBind(configPath, serviceName));
    return;
  }

  if (command === "service-url") {
    const serviceName = requiredArgument(argumentsList, "--service") as "chain_manager" | "node_manager";
    console.log(serviceUrl(configPath, serviceName));
    return;
  }

  if (command === "indexer-url") {
    console.log(loadRuntimeConfig(configPath).indexer.hasura_url);
    return;
  }

  if (command === "ui-bind") {
    console.log(loadRuntimeConfig(configPath).services.ui.bind);
    return;
  }

  if (command === "ui-url") {
    console.log(`http://${loadRuntimeConfig(configPath).services.ui.bind}`);
    return;
  }

  if (command === "deployments-dir") {
    console.log(loadRuntimeConfig(configPath).deployments_dir);
    return;
  }

  if (command === "deployment-file") {
    const chainId = Number(requiredArgument(argumentsList, "--chain-id"));
    console.log(deploymentFilePath(configPath, chainId));
    return;
  }

  if (command === "deployment-address") {
    const chainId = Number(requiredArgument(argumentsList, "--chain-id"));
    const key = requiredArgument(argumentsList, "--key");
    const deploymentPath = deploymentFilePath(configPath, chainId);
    const deployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8")) as Record<string, unknown>;
    const value = deployment[key];
    if (typeof value !== "string" || !value) {
      throw new Error(`deployment key ${key} not found in ${deploymentPath}`);
    }
    console.log(value);
    return;
  }

  if (command === "indexer-port") {
    console.log(urlPort(loadRuntimeConfig(configPath).indexer.hasura_url));
    return;
  }

  throw new Error(`unsupported command ${command}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
