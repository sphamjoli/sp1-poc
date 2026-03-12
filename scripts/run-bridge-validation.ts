import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import {
  renderBridgeReportHtml,
  type BridgeValidationReport,
  type GateResult,
} from "./render-bridge-report.ts";

interface GraphQlCountResponse {
  data?: {
    Deposit_aggregate: { aggregate: { count: number } };
    Attestation_aggregate: { aggregate: { count: number } };
  };
  errors?: Array<{ message: string }>;
}

const REPO_ROOT = process.cwd();
const README_HYPOTHESIS =
  "This proof-of-concept bridge should demonstrate practical cross-chain transfer verification using validator attestations and SP1 settlement proofs.";
const DEFAULT_GATE_TIMEOUT_MS = 10 * 60 * 1000;
const DEFAULT_FETCH_TIMEOUT_MS = 15_000;

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

function nowIso(): string {
  return new Date().toISOString();
}

function timestampId(): string {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function runCommand(command: string, extraEnv?: NodeJS.ProcessEnv): {
  ok: boolean;
  output: string;
  error?: string;
} {
  const parsedTimeout = Number(process.env.BRIDGE_GATE_TIMEOUT_MS ?? "");
  const timeoutMs = Number.isFinite(parsedTimeout) && parsedTimeout > 0
    ? parsedTimeout
    : DEFAULT_GATE_TIMEOUT_MS;

  const result = spawnSync(command, {
    shell: true,
    cwd: REPO_ROOT,
    encoding: "utf8",
    env: { ...process.env, ...extraEnv },
    maxBuffer: 1024 * 1024 * 50,
    timeout: timeoutMs,
  });

  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  if (result.status === 0) {
    return { ok: true, output };
  }

  return {
    ok: false,
    output,
    error: result.error ? String(result.error) : `exit code ${result.status ?? "unknown"}`,
  };
}

async function fetchIndexerEvidence(hasuraUrl: string, hasuraSecret: string): Promise<{
  indexedDeposits: number;
  indexedAttestations: number;
}> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(hasuraUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-hasura-admin-secret": hasuraSecret,
      },
      body: JSON.stringify({
        query: `query Evidence {\n  Deposit_aggregate { aggregate { count } }\n  Attestation_aggregate { aggregate { count } }\n}`,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`Hasura responded ${response.status}`);
    }

    const payload = (await response.json()) as GraphQlCountResponse;
    if (payload.errors?.length) {
      throw new Error(payload.errors.map((err) => err.message).join("; "));
    }
    if (!payload.data) {
      throw new Error("missing data from Hasura evidence query");
    }

    return {
      indexedDeposits: payload.data.Deposit_aggregate.aggregate.count,
      indexedAttestations: payload.data.Attestation_aggregate.aggregate.count,
    };
  } finally {
    clearTimeout(timeout);
  }
}

function addGate(
  gates: GateResult[],
  name: string,
  command: string,
  extraEnv?: NodeJS.ProcessEnv,
): { ok: boolean; output: string } {
  console.log(`[bridge-validation] running gate: ${name}`);
  const startedAt = nowIso();
  const started = Date.now();
  const result = runCommand(command, extraEnv);
  const endedAt = nowIso();
  const durationMs = Date.now() - started;

  gates.push({
    name,
    status: result.ok ? "PASS" : "FAIL",
    command,
    startedAt,
    endedAt,
    durationMs,
    details: result.ok ? result.output.slice(-4_000) : `${result.error ?? "command failed"}\n${result.output.slice(-4_000)}`,
  });

  console.log(
    `[bridge-validation] gate ${result.ok ? "PASS" : "FAIL"}: ${name} (${durationMs} ms)`,
  );

  return { ok: result.ok, output: result.output };
}

async function main(): Promise<void> {
  const hasuraUrl = cleanInput(process.env.HASURA_URL) ?? "http://localhost:8080/v1/graphql";
  const hasuraSecret =
    cleanInput(process.env.HASURA_SECRET) ??
    cleanInput(process.env.HASURA_GRAPHQL_ADMIN_SECRET) ??
    "testing";
  const prover = process.env.SP1_PROVER ?? "mock";

  const reportId = timestampId();
  const reportDir = path.join(REPO_ROOT, "artifacts", "reports", "bridge", reportId);
  fs.mkdirSync(reportDir, { recursive: true });

  const scenarioJsonPath = path.join(reportDir, "scenario.json");
  const gates: GateResult[] = [];

  addGate(gates, "Upgrade Safety Guard", "make upgrade-safety-check");
  addGate(gates, "Kill Existing Anvil", "make kill-anvil");
  addGate(gates, "Deploy Local Stack", "make deploy-local");
  addGate(gates, "Update Indexer Config", "make update-indexer-config");
  addGate(gates, "Verify Indexer Config", "make verify-indexer-config");
  addGate(gates, "Restart Indexer", "make restart-indexer");
  addGate(gates, "Ensure Indexer Ready", "make ensure-indexer-ready");
  addGate(gates, "Contract Unit Tests", "make test-contracts");
  addGate(gates, "Contract Fuzz Tests", "make test-contracts-fuzz");
  addGate(gates, "Component Tests", "make test-components");
  addGate(gates, "Bridge Program Tests", "make test-bridge");
  addGate(
    gates,
    "Bridge E2E Scenario",
    "make test-e2e-json",
    { REPORT_SCENARIO_JSON: scenarioJsonPath },
  );
  gates.push({
    name: "Bridge Scenario JSON",
    status: fs.existsSync(scenarioJsonPath) ? "PASS" : "FAIL",
    command: "parse scenario json artifact",
    startedAt: nowIso(),
    endedAt: nowIso(),
    durationMs: 0,
    details: fs.existsSync(scenarioJsonPath)
      ? `structured json found at ${scenarioJsonPath}`
      : "scenario json not found",
  });

  let indexedDeposits = 0;
  let indexedAttestations = 0;
  try {
    const evidence = await fetchIndexerEvidence(hasuraUrl, hasuraSecret);
    indexedDeposits = evidence.indexedDeposits;
    indexedAttestations = evidence.indexedAttestations;
    gates.push({
      name: "Indexed Evidence Check",
      status: indexedDeposits > 0 ? "PASS" : "FAIL",
      command: "hasura evidence query",
      startedAt: nowIso(),
      endedAt: nowIso(),
      durationMs: 0,
      details: `indexedDeposits=${indexedDeposits}, indexedAttestations=${indexedAttestations}`,
    });
  } catch (error) {
    gates.push({
      name: "Indexed Evidence Check",
      status: "FAIL",
      command: "hasura evidence query",
      startedAt: nowIso(),
      endedAt: nowIso(),
      durationMs: 0,
      details: error instanceof Error ? error.message : String(error),
    });
  }

  const passed = gates.filter((gate) => gate.status === "PASS").length;
  const failed = gates.filter((gate) => gate.status === "FAIL").length;
  const skipped = gates.filter((gate) => gate.status === "SKIP").length;

  const requiredGateNames = new Set([
    "Upgrade Safety Guard",
    "Deploy Local Stack",
    "Update Indexer Config",
    "Verify Indexer Config",
    "Restart Indexer",
    "Ensure Indexer Ready",
    "Contract Unit Tests",
    "Contract Fuzz Tests",
    "Component Tests",
    "Bridge Program Tests",
    "Bridge E2E Scenario",
    "Bridge Scenario JSON",
    "Indexed Evidence Check",
  ]);

  const requiredFailures = gates.filter(
    (gate) => requiredGateNames.has(gate.name) && gate.status !== "PASS",
  );

  const verdict = requiredFailures.length === 0 ? "SUPPORTED" : "NOT SUPPORTED";
  const rationale =
    verdict === "SUPPORTED"
      ? "All required validation gates passed, and indexed evidence confirms observable bridge activity."
      : `One or more required gates failed: ${requiredFailures.map((gate) => gate.name).join(", ",
        )}.`;

  const report: BridgeValidationReport = {
    generatedAt: nowIso(),
    repositoryRoot: REPO_ROOT,
    environment: {
      chainA: "http://127.0.0.1:8545 (chain id 1)",
      chainB: "http://127.0.0.1:8546 (chain id 8453)",
      hasuraUrl,
      prover,
    },
    hypothesis: {
      statement: README_HYPOTHESIS,
      verdict,
      rationale,
    },
    gates,
    evidence: {
      scenarioJsonPath: fs.existsSync(scenarioJsonPath) ? scenarioJsonPath : undefined,
      indexedDeposits,
      indexedAttestations,
    },
    summary: {
      passed,
      failed,
      skipped,
    },
  };

  const jsonPath = path.join(reportDir, "report.json");
  const htmlPath = path.join(reportDir, "report.html");
  fs.writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  fs.writeFileSync(htmlPath, renderBridgeReportHtml(report), "utf8");

  const latestDir = path.join(REPO_ROOT, "artifacts", "reports", "bridge");
  fs.writeFileSync(path.join(latestDir, "latest.json"), `${JSON.stringify(report, null, 2)}\n`, "utf8");
  fs.writeFileSync(path.join(latestDir, "latest.html"), renderBridgeReportHtml(report), "utf8");

  console.log(`Bridge validation report written to ${jsonPath}`);
  console.log(`Bridge validation html report written to ${htmlPath}`);

  if (verdict === "NOT SUPPORTED") {
    process.exitCode = 1;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
