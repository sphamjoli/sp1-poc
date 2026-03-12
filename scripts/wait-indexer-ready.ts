interface WaitIndexerOptions {
  hasuraUrl: string;
  hasuraSecret: string;
  timeoutMs: number;
  intervalMs: number;
}

interface GraphQlResponse<T> {
  data?: T;
  errors?: Array<{ message: string }>;
}

interface ReadinessData {
  Deposit_aggregate: { aggregate: { count: number } };
  Attestation_aggregate: { aggregate: { count: number } };
  Deposit: Array<{ id: string }>;
  Attestation: Array<{ id: string }>;
}

const READINESS_QUERY = `
query Readiness {
  Deposit_aggregate { aggregate { count } }
  Attestation_aggregate { aggregate { count } }
  Deposit(limit: 1) {
    id
    who
    user_id
    token_id
    amount
    sourceChain
    destinationChain
    blockNumber
    depositIndex
    depositRoot
  }
  Attestation(limit: 1) {
    id
    validator
    validatorManager
    sourceChainId
    sourceBlockNumber
    bridgeRoot
    stateRoot
    timestamp
    transactionHash
  }
}
`;

function cleanInput(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  const trimmed = raw.trim();
  if (trimmed.length >= 2) {
    const first = trimmed[0];
    const last = trimmed[trimmed.length - 1];
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return trimmed.slice(1, -1).trim();
    }
  }
  return trimmed;
}

function parseNumberArg(raw: string | undefined, fallback: number): number {
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    return fallback;
  }
  return Math.floor(value);
}

function parseArgs(argv: string[]): WaitIndexerOptions {
  const values: Record<string, string> = {};
  for (let i = 0; i < argv.length; i += 1) {
    const current = argv[i];
    if (!current.startsWith("--")) {
      continue;
    }
    const key = current.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      values[key] = next;
      i += 1;
    }
  }

  const argUrl = cleanInput(values.url);
  const envUrl = cleanInput(process.env.HASURA_URL);
  const argSecret = cleanInput(values.secret);
  const envSecret = cleanInput(process.env.HASURA_SECRET);
  const envAdminSecret = cleanInput(process.env.HASURA_GRAPHQL_ADMIN_SECRET);

  return {
    hasuraUrl: argUrl ?? envUrl ?? "http://localhost:8080/v1/graphql",
    hasuraSecret:
      argSecret ??
      envSecret ??
      envAdminSecret ??
      "testing",
    timeoutMs: parseNumberArg(values["timeout-ms"], 180_000),
    intervalMs: parseNumberArg(values["interval-ms"], 3_000),
  };
}

async function checkIndexerReadiness(options: WaitIndexerOptions): Promise<ReadinessData> {
  const response = await fetch(options.hasuraUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-hasura-admin-secret": options.hasuraSecret,
    },
    body: JSON.stringify({ query: READINESS_QUERY }),
  });

  if (!response.ok) {
    throw new Error(`Hasura responded ${response.status}`);
  }

  const payload = (await response.json()) as GraphQlResponse<ReadinessData>;
  if (payload.errors?.length) {
    throw new Error(payload.errors.map((error) => error.message).join("; "));
  }

  if (!payload.data) {
    throw new Error("Hasura response missing data");
  }

  return payload.data;
}

export async function waitForIndexerReady(options: WaitIndexerOptions): Promise<ReadinessData> {
  const deadline = Date.now() + options.timeoutMs;
  let lastError = "unknown error";

  while (Date.now() < deadline) {
    try {
      const result = await checkIndexerReadiness(options);
      return result;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      await new Promise((resolve) => setTimeout(resolve, options.intervalMs));
    }
  }

  throw new Error(`Indexer readiness timeout after ${options.timeoutMs}ms: ${lastError}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const options = parseArgs(process.argv.slice(2));
  waitForIndexerReady(options)
    .then((result) => {
      console.log("Indexer is ready");
      console.log(`  Deposits indexed: ${result.Deposit_aggregate.aggregate.count}`);
      console.log(`  Attestations indexed: ${result.Attestation_aggregate.aggregate.count}`);
    })
    .catch((error) => {
      console.error(error instanceof Error ? error.message : String(error));
      process.exit(1);
    });
}
