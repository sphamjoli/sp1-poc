import fs from "node:fs";
import net from "node:net";
import path from "node:path";

export const DEFAULT_RUNTIME_TEMPLATE_CONFIG_PATH = path.join("config", "runtime.local.json");
export const DEFAULT_RUNTIME_STACK_NAME = "local";

export function defaultRuntimeConfigPath(): string {
  const stackName = cleanInput(process.env.STACK_NAME) ?? DEFAULT_RUNTIME_STACK_NAME;
  return path.join("artifacts", "runtime", stackName, "runtime.generated.json");
}

export interface RuntimeChainConfig {
  id: number;
  name: string;
  rpc_url: string;
  fork_url?: string | null;
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
}

export interface RuntimeConfig {
  base_chain_id: number;
  owner_private_key?: string;
  runtime: {
    state_dir: string;
    log_dir: string;
    pid_dir: string;
  };
  services: {
    anvil: {
      state_interval_secs: number;
    };
    chain_manager: {
      bind: string;
    };
    node_manager: {
      bind: string;
      certificate_ttl_secs: number;
      reconcile_interval_secs: number;
    };
    ui: {
      bind: string;
    };
    validator: {
      poll_interval_secs: number;
      max_backoff_secs?: number;
    };
    sp1: {
      interval_secs: number;
    };
  };
  indexer: {
    hasura_url: string;
    hasura_secret: string;
  };
  validators_path: string;
  deployments_dir: string;
  chains_path?: string;
  bootstrap?: {
    gas_threshold_wei: string;
    gas_topup_wei: string;
    staking_amount_wei?: string;
  };
  chains: RuntimeChainConfig[];
}

interface RuntimeConfigFile extends Omit<RuntimeConfig, "chains"> {
  chains?: RuntimeChainConfig[];
}

function cleanInput(raw: string | undefined): string | undefined {
  if (!raw) {
    return undefined;
  }

  const trimmed = raw.trim();
  if (!trimmed) {
    return undefined;
  }

  if (trimmed.length >= 2) {
    const first = trimmed[0];
    const last = trimmed[trimmed.length - 1];
    if ((first === `"` && last === `"`) || (first === `'` && last === `'`)) {
      return trimmed.slice(1, -1).trim() || undefined;
    }
  }

  return trimmed;
}

function parsePositiveInteger(raw: string | undefined, label: string): number | undefined {
  const value = cleanInput(raw);
  if (!value) {
    return undefined;
  }

  const parsedValue = Number(value);
  if (!Number.isInteger(parsedValue) || parsedValue <= 0) {
    throw new Error(`invalid ${label}: ${value}`);
  }

  return parsedValue;
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

function loadChainsFromDirectory(configPath: string, chainsPath: string): RuntimeChainConfig[] {
  const resolvedChainsPath = resolveConfiguredPath(configPath, chainsPath);
  const chainConfigs = fs
    .readdirSync(resolvedChainsPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const chainId = Number.parseInt(entry.name, 10);
      if (!Number.isInteger(chainId) || chainId <= 0) {
        throw new Error(`invalid chain directory ${path.join(resolvedChainsPath, entry.name)}`);
      }

      const chainConfigPath = path.join(resolvedChainsPath, entry.name, "chain.json");
      if (!fs.existsSync(chainConfigPath)) {
        throw new Error(`${chainConfigPath} not found`);
      }

      const chainConfig = JSON.parse(fs.readFileSync(chainConfigPath, "utf8")) as RuntimeChainConfig;
      if (chainConfig.id !== chainId) {
        throw new Error(
          `chain config ${chainConfigPath} has id ${chainConfig.id} but directory is ${chainId}`,
        );
      }

      return chainConfig;
    })
    .sort((left, right) => left.id - right.id);

  if (chainConfigs.length === 0) {
    throw new Error(`no chain configs found in ${resolvedChainsPath}`);
  }

  return chainConfigs;
}

function expandRuntimeConfig(configPath: string, runtimeConfigFile: RuntimeConfigFile): RuntimeConfig {
  const inlineChains = runtimeConfigFile.chains ?? [];
  const chains = inlineChains.length > 0
    ? inlineChains
    : runtimeConfigFile.chains_path
      ? loadChainsFromDirectory(configPath, runtimeConfigFile.chains_path)
      : [];

  return {
    ...runtimeConfigFile,
    chains,
  };
}

function readJsonConfig(configPath: string): RuntimeConfig {
  if (!fs.existsSync(configPath)) {
    throw new Error(`${configPath} not found`);
  }

  const runtimeConfigFile = JSON.parse(fs.readFileSync(configPath, "utf8")) as RuntimeConfigFile;
  return expandRuntimeConfig(configPath, runtimeConfigFile);
}

function bindHost(bind: string): string {
  const separatorIndex = bind.lastIndexOf(":");
  if (separatorIndex < 0) {
    throw new Error(`invalid bind address: ${bind}`);
  }

  return bind.slice(0, separatorIndex);
}

function bindPort(bind: string): number {
  const separatorIndex = bind.lastIndexOf(":");
  if (separatorIndex < 0) {
    throw new Error(`invalid bind address: ${bind}`);
  }

  return parsePositiveInteger(bind.slice(separatorIndex + 1), "bind port") ?? 0;
}

function withBindPort(bind: string, port: number): string {
  return `${bindHost(bind)}:${port}`;
}

function urlPort(url: string): number {
  const parsedUrl = new URL(url);
  const port = parsedUrl.port ? Number(parsedUrl.port) : parsedUrl.protocol === "https:" ? 443 : 80;
  if (!Number.isInteger(port) || port <= 0 || port > 65_535) {
    throw new Error(`invalid URL port: ${url}`);
  }
  return port;
}

function urlHost(url: string): string {
  return new URL(url).hostname;
}

function withUrlPort(url: string, port: number): string {
  const parsedUrl = new URL(url);
  parsedUrl.port = String(port);
  return parsedUrl.toString();
}

function envRuntimeConfigPath(): string | undefined {
  return cleanInput(process.env.RUNTIME_CONFIG);
}

export function runtimeTemplateConfigPath(): string {
  return cleanInput(process.env.RUNTIME_TEMPLATE_CONFIG) ?? DEFAULT_RUNTIME_TEMPLATE_CONFIG_PATH;
}

export function runtimeConfigPath(): string {
  return envRuntimeConfigPath() ?? defaultRuntimeConfigPath();
}

function isGeneratedRuntimeConfigPath(configPath: string): boolean {
  const normalizedPath = path.normalize(configPath);
  return normalizedPath.includes(path.join("artifacts", "runtime"));
}

function overrideChainUrl(chain: RuntimeChainConfig): string | undefined {
  const rpcUrlOverride = cleanInput(process.env[`RPC_URL_${chain.id}`]);
  if (rpcUrlOverride) {
    return rpcUrlOverride;
  }

  const portOverride = parsePositiveInteger(
    process.env[`ANVIL_PORT_${chain.id}`],
    `ANVIL_PORT_${chain.id}`,
  );
  if (!portOverride) {
    return undefined;
  }

  return withUrlPort(chain.rpc_url, portOverride);
}

function applyEnvironmentOverrides(runtimeConfig: RuntimeConfig): RuntimeConfig {
  const updatedConfig: RuntimeConfig = structuredClone(runtimeConfig);

  for (const chain of updatedConfig.chains) {
    const chainOverride = overrideChainUrl(chain);
    if (chainOverride) {
      chain.rpc_url = chainOverride;
    }
  }

  const chainManagerBind = cleanInput(process.env.CHAIN_MANAGER_BIND);
  const chainManagerPort = parsePositiveInteger(process.env.CHAIN_MANAGER_PORT, "CHAIN_MANAGER_PORT");
  if (chainManagerBind) {
    updatedConfig.services.chain_manager.bind = chainManagerBind;
  } else if (chainManagerPort) {
    updatedConfig.services.chain_manager.bind = withBindPort(
      updatedConfig.services.chain_manager.bind,
      chainManagerPort,
    );
  }

  const nodeManagerBind = cleanInput(process.env.NODE_MANAGER_BIND);
  const nodeManagerPort = parsePositiveInteger(process.env.NODE_MANAGER_PORT, "NODE_MANAGER_PORT");
  if (nodeManagerBind) {
    updatedConfig.services.node_manager.bind = nodeManagerBind;
  } else if (nodeManagerPort) {
    updatedConfig.services.node_manager.bind = withBindPort(
      updatedConfig.services.node_manager.bind,
      nodeManagerPort,
    );
  }

  const uiBind = cleanInput(process.env.UI_BIND);
  const uiPort = parsePositiveInteger(process.env.UI_PORT, "UI_PORT");
  if (uiBind) {
    updatedConfig.services.ui.bind = uiBind;
  } else if (uiPort) {
    updatedConfig.services.ui.bind = withBindPort(updatedConfig.services.ui.bind, uiPort);
  }

  const hasuraUrl = cleanInput(process.env.HASURA_URL);
  if (hasuraUrl) {
    updatedConfig.indexer.hasura_url = hasuraUrl;
  } else {
    const hasuraPort = parsePositiveInteger(process.env.HASURA_EXTERNAL_PORT, "HASURA_EXTERNAL_PORT");
    if (hasuraPort) {
      updatedConfig.indexer.hasura_url = withUrlPort(updatedConfig.indexer.hasura_url, hasuraPort);
    }
  }

  const hasuraSecret = cleanInput(process.env.HASURA_SECRET)
    ?? cleanInput(process.env.HASURA_GRAPHQL_ADMIN_SECRET);
  if (hasuraSecret) {
    updatedConfig.indexer.hasura_secret = hasuraSecret;
  }

  const validatorPollInterval = parsePositiveInteger(
    process.env.VALIDATOR_POLL_INTERVAL_SECS,
    "VALIDATOR_POLL_INTERVAL_SECS",
  );
  if (validatorPollInterval) {
    updatedConfig.services.validator.poll_interval_secs = validatorPollInterval;
  }

  const validatorMaxBackoff = parsePositiveInteger(
    process.env.VALIDATOR_MAX_BACKOFF_SECS,
    "VALIDATOR_MAX_BACKOFF_SECS",
  );
  if (validatorMaxBackoff) {
    updatedConfig.services.validator.max_backoff_secs = validatorMaxBackoff;
  }

  const sp1Interval = parsePositiveInteger(process.env.SP1_INTERVAL_SECS, "SP1_INTERVAL_SECS");
  if (sp1Interval) {
    updatedConfig.services.sp1.interval_secs = sp1Interval;
  }

  return updatedConfig;
}

export function loadRuntimeConfig(configPath = runtimeConfigPath()): RuntimeConfig {
  const runtimeConfig = readJsonConfig(configPath);
  if (isGeneratedRuntimeConfigPath(configPath)) {
    return runtimeConfig;
  }
  return applyEnvironmentOverrides(runtimeConfig);
}

async function canBindPort(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    const finish = (value: boolean): void => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(value);
    };

    socket.setTimeout(500);
    socket.once("connect", () => finish(false));
    socket.once("timeout", () => finish(false));
    socket.once("error", (error: NodeJS.ErrnoException) => {
      if (error.code === "ECONNREFUSED" || error.code === "EPERM") {
        finish(true);
        return;
      }

      finish(false);
    });
    socket.connect(port, host);
  });
}

async function httpReachable(url: string): Promise<boolean> {
  try {
    const response = await fetch(url, {
      method: "GET",
      signal: AbortSignal.timeout(1_000),
    });
    return response.status >= 200 || response.status < 600;
  } catch {
    return false;
  }
}

async function rpcMatchesChain(url: string, chainId: number): Promise<boolean> {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_chainId",
        params: [],
      }),
      signal: AbortSignal.timeout(1_000),
    });

    if (!response.ok) {
      return false;
    }

    const payload = (await response.json()) as { result?: string };
    if (!payload.result) {
      return false;
    }

    return Number.parseInt(payload.result, 16) === chainId;
  } catch {
    return false;
  }
}

async function nextAvailablePort(host: string, startPort: number): Promise<number> {
  for (let port = startPort; port < startPort + 256; port += 1) {
    if (await canBindPort(host, port)) {
      return port;
    }
  }

  throw new Error(`unable to find a free port near ${host}:${startPort}`);
}

async function resolveChainRpcUrl(
  chain: RuntimeChainConfig,
  existingRuntimeConfig: RuntimeConfig | undefined,
  reservedPorts: Set<number>,
): Promise<string> {
  const explicitOverride = overrideChainUrl(chain);
  if (explicitOverride) {
    reservePort(reservedPorts, urlPort(explicitOverride), `chain ${chain.id}`);
    return explicitOverride;
  }

  const existingChain = existingRuntimeConfig?.chains.find((candidate) => candidate.id === chain.id);
  if (
    existingChain &&
    !reservedPorts.has(urlPort(existingChain.rpc_url)) &&
    (
      await rpcMatchesChain(existingChain.rpc_url, chain.id) ||
      await canBindPort(urlHost(existingChain.rpc_url), urlPort(existingChain.rpc_url))
    )
  ) {
    reservePort(reservedPorts, urlPort(existingChain.rpc_url), `chain ${chain.id}`);
    return existingChain.rpc_url;
  }

  const host = urlHost(chain.rpc_url);
  if (!reservedPorts.has(urlPort(chain.rpc_url)) && await canBindPort(host, urlPort(chain.rpc_url))) {
    reservePort(reservedPorts, urlPort(chain.rpc_url), `chain ${chain.id}`);
    return chain.rpc_url;
  }

  const resolvedPort = await nextAvailablePortWithReservations(host, urlPort(chain.rpc_url) + 1, reservedPorts);
  reservePort(reservedPorts, resolvedPort, `chain ${chain.id}`);
  return withUrlPort(chain.rpc_url, resolvedPort);
}

async function resolveBind(
  templateBind: string,
  existingBind: string | undefined,
  explicitBind: string | undefined,
  explicitPort: number | undefined,
  probe: (bind: string) => Promise<boolean>,
  reservedPorts: Set<number>,
  label: string,
): Promise<string> {
  if (explicitBind) {
    reservePort(reservedPorts, bindPort(explicitBind), label);
    return explicitBind;
  }

  const preferredBind = explicitPort ? withBindPort(templateBind, explicitPort) : templateBind;
  if (explicitPort) {
    const existingMatchesPreferred = existingBind === preferredBind;
    if (
      existingMatchesPreferred &&
      !reservedPorts.has(bindPort(preferredBind)) &&
      (
        await probe(preferredBind) ||
        await canBindPort(bindHost(preferredBind), bindPort(preferredBind))
      )
    ) {
      reservePort(reservedPorts, bindPort(preferredBind), label);
      return preferredBind;
    }

    const host = bindHost(preferredBind);
    const preferredPort = bindPort(preferredBind);
    if (!reservedPorts.has(preferredPort) && await canBindPort(host, preferredPort)) {
      reservePort(reservedPorts, preferredPort, label);
      return preferredBind;
    }

    const resolvedPort = await nextAvailablePortWithReservations(host, preferredPort + 1, reservedPorts);
    reservePort(reservedPorts, resolvedPort, label);
    return withBindPort(preferredBind, resolvedPort);
  }

  if (existingBind && !reservedPorts.has(bindPort(existingBind))) {
    if (
      await probe(existingBind) ||
      await canBindPort(bindHost(existingBind), bindPort(existingBind))
    ) {
      reservePort(reservedPorts, bindPort(existingBind), label);
      return existingBind;
    }
  }

  const host = bindHost(preferredBind);
  const preferredPort = bindPort(preferredBind);
  if (!reservedPorts.has(preferredPort) && await canBindPort(host, preferredPort)) {
    reservePort(reservedPorts, preferredPort, label);
    return preferredBind;
  }

  const resolvedPort = await nextAvailablePortWithReservations(host, preferredPort + 1, reservedPorts);
  reservePort(reservedPorts, resolvedPort, label);
  return withBindPort(preferredBind, resolvedPort);
}

async function resolveIndexerUrl(
  templateUrl: string,
  existingRuntimeConfig: RuntimeConfig | undefined,
  reservedPorts: Set<number>,
): Promise<string> {
  const explicitUrl = cleanInput(process.env.HASURA_URL);
  if (explicitUrl) {
    reservePort(reservedPorts, urlPort(explicitUrl), "indexer");
    return explicitUrl;
  }

  const explicitPort = parsePositiveInteger(process.env.HASURA_EXTERNAL_PORT, "HASURA_EXTERNAL_PORT");
  const preferredUrl = explicitPort ? withUrlPort(templateUrl, explicitPort) : templateUrl;
  const existingUrl = existingRuntimeConfig?.indexer.hasura_url;
  if (explicitPort) {
    const existingMatchesPreferred = existingUrl === preferredUrl;
    if (
      existingMatchesPreferred &&
      !reservedPorts.has(urlPort(preferredUrl)) &&
      (
        await httpReachable(preferredUrl) ||
        await canBindPort(urlHost(preferredUrl), urlPort(preferredUrl))
      )
    ) {
      reservePort(reservedPorts, urlPort(preferredUrl), "indexer");
      return preferredUrl;
    }

    const host = urlHost(preferredUrl);
    const preferredPort = urlPort(preferredUrl);
    if (!reservedPorts.has(preferredPort) && await canBindPort(host, preferredPort)) {
      reservePort(reservedPorts, preferredPort, "indexer");
      return preferredUrl;
    }

    const resolvedPort = await nextAvailablePortWithReservations(host, preferredPort + 1, reservedPorts);
    reservePort(reservedPorts, resolvedPort, "indexer");
    return withUrlPort(preferredUrl, resolvedPort);
  }

  if (existingUrl && !reservedPorts.has(urlPort(existingUrl))) {
    if (
      await httpReachable(existingUrl) ||
      await canBindPort(urlHost(existingUrl), urlPort(existingUrl))
    ) {
      reservePort(reservedPorts, urlPort(existingUrl), "indexer");
      return existingUrl;
    }
  }

  const host = urlHost(preferredUrl);
  const preferredPort = urlPort(preferredUrl);
  if (!reservedPorts.has(preferredPort) && await canBindPort(host, preferredPort)) {
    reservePort(reservedPorts, preferredPort, "indexer");
    return preferredUrl;
  }

  const resolvedPort = await nextAvailablePortWithReservations(host, preferredPort + 1, reservedPorts);
  reservePort(reservedPorts, resolvedPort, "indexer");
  return withUrlPort(preferredUrl, resolvedPort);
}

function reservePort(reservedPorts: Set<number>, port: number, label: string): void {
  if (reservedPorts.has(port)) {
    throw new Error(`runtime port ${port} is already assigned before resolving ${label}`);
  }

  reservedPorts.add(port);
}

async function nextAvailablePortWithReservations(
  host: string,
  startPort: number,
  reservedPorts: Set<number>,
): Promise<number> {
  for (let port = startPort; port < startPort + 256; port += 1) {
    if (reservedPorts.has(port)) {
      continue;
    }

    if (await canBindPort(host, port)) {
      return port;
    }
  }

  throw new Error(`unable to find a free reserved port near ${host}:${startPort}`);
}

export async function renderRuntimeConfig(
  templatePath = runtimeTemplateConfigPath(),
  outputPath = runtimeConfigPath(),
): Promise<RuntimeConfig> {
  const templateConfig = readJsonConfig(templatePath);
  const existingRuntimeConfig = fs.existsSync(outputPath)
    ? readJsonConfig(outputPath)
    : undefined;
  const renderedConfig: RuntimeConfig = structuredClone(templateConfig);
  const reservedPorts = new Set<number>();

  renderedConfig.chains = [];
  for (const chain of templateConfig.chains) {
    const rpc_url = await resolveChainRpcUrl(chain, existingRuntimeConfig, reservedPorts);
    renderedConfig.chains.push({
      ...chain,
      rpc_url,
    });
  }

  renderedConfig.services.chain_manager.bind = await resolveBind(
    templateConfig.services.chain_manager.bind,
    existingRuntimeConfig?.services.chain_manager.bind,
    cleanInput(process.env.CHAIN_MANAGER_BIND),
    parsePositiveInteger(process.env.CHAIN_MANAGER_PORT, "CHAIN_MANAGER_PORT"),
    async (bind) => httpReachable(`http://${bind}`),
    reservedPorts,
    "chain-manager",
  );

  renderedConfig.services.node_manager.bind = await resolveBind(
    templateConfig.services.node_manager.bind,
    existingRuntimeConfig?.services.node_manager.bind,
    cleanInput(process.env.NODE_MANAGER_BIND),
    parsePositiveInteger(process.env.NODE_MANAGER_PORT, "NODE_MANAGER_PORT"),
    async (bind) => httpReachable(`http://${bind}/healthz`),
    reservedPorts,
    "node-manager",
  );

  renderedConfig.services.ui.bind = await resolveBind(
    templateConfig.services.ui.bind,
    existingRuntimeConfig?.services.ui.bind,
    cleanInput(process.env.UI_BIND),
    parsePositiveInteger(process.env.UI_PORT, "UI_PORT"),
    async (bind) => httpReachable(`http://${bind}`),
    reservedPorts,
    "ui",
  );

  renderedConfig.indexer.hasura_url = await resolveIndexerUrl(
    templateConfig.indexer.hasura_url,
    existingRuntimeConfig,
    reservedPorts,
  );

  const hasuraSecret = cleanInput(process.env.HASURA_SECRET)
    ?? cleanInput(process.env.HASURA_GRAPHQL_ADMIN_SECRET);
  if (hasuraSecret) {
    renderedConfig.indexer.hasura_secret = hasuraSecret;
  }

  const outputDirectory = path.dirname(outputPath);
  renderedConfig.runtime.state_dir = path.relative(process.cwd(), path.join(outputDirectory, "state"));
  renderedConfig.runtime.log_dir = path.relative(process.cwd(), path.join(outputDirectory, "logs"));
  renderedConfig.runtime.pid_dir = path.relative(process.cwd(), path.join(outputDirectory, "pids"));
  renderedConfig.deployments_dir = path.relative(process.cwd(), path.join(outputDirectory, "deployments"));
  delete renderedConfig.chains_path;
  fs.mkdirSync(outputDirectory, { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(renderedConfig, null, 2)}\n`, "utf8");

  return renderedConfig;
}

export function chainById(runtimeConfig: RuntimeConfig, chainId: number): RuntimeChainConfig {
  const chain = runtimeConfig.chains.find((candidate) => candidate.id === chainId);
  if (!chain) {
    throw new Error(`chain ${chainId} not found in runtime config`);
  }
  return chain;
}
