import fs from "node:fs";
import path from "node:path";
import {
  loadRuntimeConfig,
  runtimeConfigPath,
  type RuntimeConfig,
} from "./runtime-config-lib.ts";

interface ValidatorCatalogEntry {
  name: string;
}

interface ComposeDependency {
  serviceName: string;
  condition?: "service_started" | "service_healthy";
}

function bindPort(bind: string): number {
  const separatorIndex = bind.lastIndexOf(":");
  if (separatorIndex < 0) {
    throw new Error(`invalid bind address ${bind}`);
  }

  return Number(bind.slice(separatorIndex + 1));
}

function urlPort(url: string): number {
  const parsedUrl = new URL(url);
  return Number(parsedUrl.port || (parsedUrl.protocol === "https:" ? "443" : "80"));
}

function relativePath(fromDirectory: string, toPath: string): string {
  const relativeValue = path.relative(fromDirectory, toPath).replaceAll(path.sep, "/");
  return relativeValue || ".";
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

function loadValidatorNames(runtimeConfig: RuntimeConfig, configPath: string): string[] {
  const validatorCatalogPath = resolveConfiguredPath(configPath, runtimeConfig.validators_path);
  const parsedValue = JSON.parse(fs.readFileSync(validatorCatalogPath, "utf8")) as ValidatorCatalogEntry[];

  if (!Array.isArray(parsedValue) || parsedValue.length === 0) {
    throw new Error(`validator catalog ${validatorCatalogPath} is empty`);
  }

  const validatorNames = parsedValue.map((entry) => entry.name?.trim()).filter(Boolean) as string[];
  if (validatorNames.length !== parsedValue.length) {
    throw new Error(`validator catalog ${validatorCatalogPath} contains invalid entries`);
  }

  return [...new Set(validatorNames)].sort();
}

function serializeDependsOn(dependencies: ComposeDependency[]): string {
  if (dependencies.length === 0) {
    return "";
  }

  const lines = dependencies.map(
    (dependency) =>
      `      ${dependency.serviceName}:\n        condition: ${dependency.condition ?? "service_started"}`,
  );

  return `    depends_on:\n${lines.join("\n")}\n`;
}

function serializeEnvironment(environmentEntries: Array<[string, string]>): string {
  return environmentEntries
    .map(([key, value]) => `      ${key}: ${JSON.stringify(value)}`)
    .join("\n");
}

function serializeExtraHosts(entries: string[]): string {
  if (entries.length === 0) {
    return "";
  }

  return `    extra_hosts:\n${entries.map((entry) => `      - ${JSON.stringify(entry)}`).join("\n")}\n`;
}

function runtimeContainerConfigPath(configPath: string): string {
  const relativeConfigPath = path.relative(process.cwd(), path.resolve(configPath)).replaceAll(path.sep, "/");
  return `/workspace/${relativeConfigPath}`;
}

function runtimeEnvironment(
  runtimeConfig: RuntimeConfig,
  configPath: string,
  overrides: Array<[string, string]> = [],
): string {
  const environmentEntries: Array<[string, string]> = [
    ["RUNTIME_CONFIG", runtimeContainerConfigPath(configPath)],
    ["RUST_LOG", "info"],
  ];

  for (const chain of runtimeConfig.chains) {
    environmentEntries.push(["RPC_URL_" + chain.id, `http://anvil-${chain.id}:${urlPort(chain.rpc_url)}/`]);
  }

  environmentEntries.push(...overrides);
  return serializeEnvironment(environmentEntries);
}

function serializeAnvilService(
  composeDirectory: string,
  chain: RuntimeConfig["chains"][number],
  stateIntervalSeconds: number,
): string {
  const rpcPort = urlPort(chain.rpc_url);
  const stateDirectory = `./state/anvil/${chain.id}`;
  const contractsContext = relativePath(composeDirectory, path.join(process.cwd(), "contracts"));
  const forkUrlArgument = chain.fork_url && !process.env.ANVIL_NO_FORK
    ? `\n      - "--fork-url"\n      - "${chain.fork_url}"`
    : "";

  return `  anvil-${chain.id}:
    build:
      context: ${contractsContext}
      dockerfile: dockerfile
    restart: unless-stopped
    command:
      - "--host"
      - "0.0.0.0"
      - "--port"
      - "${rpcPort}"
      - "--chain-id"
      - "${chain.id}"
      - "--code-size-limit"
      - "999999"
      - "--silent"${forkUrlArgument}
      - "--state"
      - "/var/lib/anvil/${chain.id}"
      - "--state-interval"
      - "${stateIntervalSeconds}"
    ports:
      - "${rpcPort}:${rpcPort}"
    volumes:
      - ${stateDirectory}:/var/lib/anvil/${chain.id}
    healthcheck:
      test: ["CMD", "/home/foundry/.foundry/bin/cast", "chain-id", "--rpc-url", "http://127.0.0.1:${rpcPort}"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 5s
`;
}

function serializeIndexerServices(composeDirectory: string, runtimeConfig: RuntimeConfig): string {
  const hasuraPort = urlPort(runtimeConfig.indexer.hasura_url);
  const indexerContext = relativePath(composeDirectory, path.join(process.cwd(), "indexer"));

  return `  envio-postgres:
    image: postgres:16
    restart: unless-stopped
    ports:
      - "${hasuraPort + 1000}:5432"
    volumes:
      - envio_postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${runtimeConfig.indexer.hasura_secret}
      POSTGRES_USER: postgres
      POSTGRES_DB: envio-dev

  graphql-engine:
    image: hasura/graphql-engine:v2.36.0
    restart: unless-stopped
    depends_on:
      envio-postgres:
        condition: service_started
    ports:
      - "${hasuraPort}:8080"
    environment:
      HASURA_GRAPHQL_DATABASE_URL: postgres://postgres:${runtimeConfig.indexer.hasura_secret}@envio-postgres:5432/envio-dev
      HASURA_GRAPHQL_ENABLE_CONSOLE: "true"
      HASURA_GRAPHQL_ENABLED_LOG_TYPES: startup,http-log,webhook-log,websocket-log,query-log
      HASURA_GRAPHQL_NO_OF_RETRIES: "10"
      HASURA_GRAPHQL_ADMIN_SECRET: ${runtimeConfig.indexer.hasura_secret}
      HASURA_GRAPHQL_STRINGIFY_NUMERIC_TYPES: "true"
      HASURA_GRAPHQL_DEV_MODE: "true"
      PORT: "8080"
      HASURA_GRAPHQL_UNAUTHORIZED_ROLE: public
    healthcheck:
      test: ["CMD", "sh", "-lc", "timeout 1s bash -c ':> /dev/tcp/127.0.0.1/8080' || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 50
      start_period: 5s

  envio-indexer:
    build:
      context: ${indexerContext}
      dockerfile: Dockerfile
    restart: unless-stopped
    depends_on:
      graphql-engine:
        condition: service_healthy
${serializeExtraHosts(["host.docker.internal:host-gateway"])}    environment:
      ENVIO_POSTGRES_PASSWORD: ${runtimeConfig.indexer.hasura_secret}
      ENVIO_PG_HOST: envio-postgres
      ENVIO_PG_PORT: 5432
      ENVIO_PG_USER: postgres
      ENVIO_PG_DATABASE: envio-dev
      PG_PASSWORD: ${runtimeConfig.indexer.hasura_secret}
      PG_HOST: envio-postgres
      PG_PORT: 5432
      PG_USER: postgres
      PG_DATABASE: envio-dev
      HASURA_GRAPHQL_ENDPOINT: http://graphql-engine:8080/v1/metadata
      HASURA_GRAPHQL_ADMIN_SECRET: ${runtimeConfig.indexer.hasura_secret}
      HASURA_SERVICE_HOST: graphql-engine
      HASURA_SERVICE_PORT: 8080
      CONFIG_FILE: config.yaml
      LOG_LEVEL: trace
      LOG_STRATEGY: console-pretty
      TUI_OFF: "true"
`;
}

function serializeUiService(composeDirectory: string, runtimeConfig: RuntimeConfig): string {
  const uiPort = bindPort(runtimeConfig.services.ui.bind);
  const webContext = relativePath(composeDirectory, path.join(process.cwd(), "apps", "web"));
  const nodeManagerPort = bindPort(runtimeConfig.services.node_manager.bind);

  return `  ui:
    build:
      context: ${webContext}
      dockerfile: Dockerfile
    restart: unless-stopped
    depends_on:
      graphql-engine:
        condition: service_healthy
    environment:
      UI_PORT: "${uiPort}"
      VITE_HASURA_URL: "${runtimeConfig.indexer.hasura_url}"
      VITE_NODE_MANAGER_URL: "http://localhost:${nodeManagerPort}"
      VITE_SWAP_MODE: "local"
    ports:
      - "${uiPort}:${uiPort}"
`;
}

function serializeRuntimeService(
  composeDirectory: string,
  runtimeConfig: RuntimeConfig,
  configPath: string,
  serviceName: string,
  command: string[],
  options: {
    dependsOn?: ComposeDependency[];
    healthcheck?: string;
    ports?: number[];
    overrides?: Array<[string, string]>;
    restart?: string;
  } = {},
): string {
  const runtimeContext = relativePath(composeDirectory, process.cwd());
  const portLines = options.ports?.length
    ? `    ports:\n${options.ports.map((port) => `      - "${port}:${port}"`).join("\n")}\n`
    : "";
  const dependsOn = serializeDependsOn(options.dependsOn ?? []);
  const healthcheck = options.healthcheck ?? "";
  const restartPolicy = options.restart ?? "unless-stopped";

  return `  ${serviceName}:
    build:
      context: ${runtimeContext}
      dockerfile: Dockerfile.runtime
    working_dir: /workspace
    restart: ${restartPolicy}
    volumes:
      - ${runtimeContext}:/workspace
${dependsOn}    environment:
${runtimeEnvironment(runtimeConfig, configPath, options.overrides)}
    command: ${JSON.stringify(command)}
${portLines}${healthcheck}`;
}

function serializeRuntimeServices(runtimeConfig: RuntimeConfig, configPath: string): string {
  const composeDirectory = path.dirname(path.resolve(configPath));
  const chainManagerPort = bindPort(runtimeConfig.services.chain_manager.bind);
  const nodeManagerPort = bindPort(runtimeConfig.services.node_manager.bind);
  const chainDependencies = runtimeConfig.chains.map((chain) => ({
    serviceName: `anvil-${chain.id}`,
    condition: "service_healthy" as const,
  }));
  const validatorNames = loadValidatorNames(runtimeConfig, configPath);
  const internalHasuraUrl = "http://graphql-engine:8080/v1/graphql";

  const chainManagerService = serializeRuntimeService(
    composeDirectory,
    runtimeConfig,
    configPath,
    "chain-manager",
    ["/usr/local/bin/chain-manager", "--config", runtimeContainerConfigPath(configPath)],
    {
      dependsOn: chainDependencies,
      ports: [chainManagerPort],
      overrides: [["CHAIN_MANAGER_BIND", `0.0.0.0:${chainManagerPort}`]],
    },
  );

  const bootstrapService = serializeRuntimeService(
    composeDirectory,
    runtimeConfig,
    configPath,
    "validator-set-bootstrap",
    ["/usr/local/bin/validator-utils", "bootstrap", "--config", runtimeContainerConfigPath(configPath)],
    {
      dependsOn: chainDependencies,
      restart: "no",
    },
  );

  const nodeManagerService = serializeRuntimeService(
    composeDirectory,
    runtimeConfig,
    configPath,
    "node-manager",
    ["/usr/local/bin/node-manager", "--config", runtimeContainerConfigPath(configPath)],
    {
      dependsOn: chainDependencies,
      ports: [nodeManagerPort],
      overrides: [["NODE_MANAGER_BIND", `0.0.0.0:${nodeManagerPort}`]],
      healthcheck:
        `    healthcheck:\n` +
        `      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:${nodeManagerPort}/healthz"]\n` +
        `      interval: 5s\n` +
        `      timeout: 3s\n` +
        `      retries: 20\n` +
        `      start_period: 5s\n`,
    },
  );

  const validatorServices = validatorNames
    .map((validatorName) =>
      serializeRuntimeService(
        composeDirectory,
        runtimeConfig,
        configPath,
        `validator-${validatorName}`,
        [
          "/usr/local/bin/bridge-validator",
          "--config",
          runtimeContainerConfigPath(configPath),
          "--validator",
          validatorName,
        ],
        {
          dependsOn: [
            { serviceName: "graphql-engine", condition: "service_healthy" },
            { serviceName: "chain-manager", condition: "service_started" },
            { serviceName: "node-manager", condition: "service_healthy" },
          ],
          overrides: [
            ["CHAIN_MANAGER_BIND", `chain-manager:${chainManagerPort}`],
            ["NODE_MANAGER_BIND", `node-manager:${nodeManagerPort}`],
            ["HASURA_URL", internalHasuraUrl],
          ],
        },
      ),
    )
    .join("\n\n");

  const sp1Service = serializeRuntimeService(
    composeDirectory,
    runtimeConfig,
    configPath,
    "sp1",
    [
      "/usr/local/bin/evm",
      "--config",
      runtimeContainerConfigPath(configPath),
      "--loop",
      "--interval-secs",
      String(runtimeConfig.services.sp1.interval_secs),
    ],
    {
      dependsOn: [
        { serviceName: "graphql-engine", condition: "service_healthy" },
        { serviceName: "chain-manager", condition: "service_started" },
      ],
      overrides: [
        ["CHAIN_MANAGER_BIND", `chain-manager:${chainManagerPort}`],
        ["HASURA_URL", internalHasuraUrl],
        ["SP1_PROVER", "mock"],
      ],
    },
  );

  return [chainManagerService, bootstrapService, nodeManagerService, validatorServices, sp1Service]
    .filter((value) => value.trim().length > 0)
    .join("\n\n");
}

function buildComposeFile(runtimeConfig: RuntimeConfig, configPath: string): string {
  const composeDirectory = path.dirname(path.resolve(configPath));
  const anvilServices = runtimeConfig.chains
    .map((chain) => serializeAnvilService(composeDirectory, chain, runtimeConfig.services.anvil.state_interval_secs))
    .join("\n");

  return `services:
${anvilServices}
${serializeIndexerServices(composeDirectory, runtimeConfig)}
${serializeUiService(composeDirectory, runtimeConfig)}
${serializeRuntimeServices(runtimeConfig, configPath)}

volumes:
  envio_postgres_data:
`;
}

function main(): void {
  const configPath = runtimeConfigPath();
  const runtimeConfig = loadRuntimeConfig(configPath);
  const composeFilePath = path.join(path.dirname(configPath), "docker-compose.generated.yaml");
  const composeFileContents = buildComposeFile(runtimeConfig, configPath);

  fs.mkdirSync(path.dirname(composeFilePath), { recursive: true });
  fs.writeFileSync(composeFilePath, `${composeFileContents.trimEnd()}\n`, "utf8");

  console.log(`Generated ${composeFilePath}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
