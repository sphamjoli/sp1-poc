import fs from "node:fs";
import path from "node:path";

export interface GateResult {
  name: string;
  status: "PASS" | "FAIL" | "SKIP";
  command: string;
  startedAt: string;
  endedAt: string;
  durationMs: number;
  details?: string;
}

export interface BridgeValidationReport {
  generatedAt: string;
  repositoryRoot: string;
  environment: {
    chainA: string;
    chainB: string;
    hasuraUrl: string;
    prover: string;
  };
  hypothesis: {
    statement: string;
    verdict: "SUPPORTED" | "NOT SUPPORTED";
    rationale: string;
  };
  gates: GateResult[];
  evidence: {
    scenarioJsonPath?: string;
    indexedDeposits: number;
    indexedAttestations: number;
  };
  summary: {
    passed: number;
    failed: number;
    skipped: number;
  };
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function renderBridgeReportHtml(report: BridgeValidationReport): string {
  const gateRows = report.gates
    .map((gate) => {
      const color = gate.status === "PASS" ? "#14532d" : gate.status === "FAIL" ? "#7f1d1d" : "#334155";
      const bg = gate.status === "PASS" ? "#dcfce7" : gate.status === "FAIL" ? "#fee2e2" : "#e2e8f0";
      return `<tr>
  <td>${escapeHtml(gate.name)}</td>
  <td><span style="background:${bg};color:${color};padding:2px 8px;border-radius:999px;font-weight:700;">${gate.status}</span></td>
  <td><code>${escapeHtml(gate.command)}</code></td>
  <td>${gate.durationMs}ms</td>
  <td>${escapeHtml(gate.details ?? "")}</td>
</tr>`;
    })
    .join("\n");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Bridge Validation Report</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f8fafc;
      --card: #ffffff;
      --text: #0f172a;
      --muted: #475569;
      --line: #cbd5e1;
      --accent: #0f766e;
    }
    body { margin: 0; background: radial-gradient(circle at top left, #e2e8f0 0%, var(--bg) 35%); color: var(--text); font-family: "IBM Plex Sans", "Avenir Next", sans-serif; }
    .container { max-width: 1120px; margin: 0 auto; padding: 24px; }
    .hero { background: linear-gradient(125deg, #134e4a 0%, #0f766e 55%, #115e59 100%); color: #f0fdfa; border-radius: 20px; padding: 24px; box-shadow: 0 8px 28px rgba(15, 118, 110, 0.25); }
    .hero h1 { margin: 0 0 6px; font-size: 32px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 16px; margin-top: 18px; }
    .card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
    h2 { margin-top: 0; font-size: 18px; }
    p, li { color: var(--muted); }
    table { width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; }
    th, td { border-bottom: 1px solid var(--line); text-align: left; padding: 10px; vertical-align: top; font-size: 14px; }
    th { background: #f1f5f9; color: #0f172a; }
    code { font-family: "JetBrains Mono", monospace; font-size: 12px; }
    .verdict { font-size: 28px; font-weight: 800; margin: 0; }
    .supported { color: #166534; }
    .unsupported { color: #991b1b; }
  </style>
</head>
<body>
  <div class="container">
    <section class="hero">
      <h1>Bridge Validation Report</h1>
      <p>Generated at ${escapeHtml(report.generatedAt)}</p>
      <p>Repository: <code>${escapeHtml(report.repositoryRoot)}</code></p>
    </section>

    <section class="grid">
      <article class="card">
        <h2>Hypothesis</h2>
        <p>${escapeHtml(report.hypothesis.statement)}</p>
        <p class="verdict ${report.hypothesis.verdict === "SUPPORTED" ? "supported" : "unsupported"}">${report.hypothesis.verdict}</p>
        <p>${escapeHtml(report.hypothesis.rationale)}</p>
      </article>
      <article class="card">
        <h2>Environment</h2>
        <ul>
          <li>Chain A: <code>${escapeHtml(report.environment.chainA)}</code></li>
          <li>Chain B: <code>${escapeHtml(report.environment.chainB)}</code></li>
          <li>Hasura: <code>${escapeHtml(report.environment.hasuraUrl)}</code></li>
          <li>Prover: <code>${escapeHtml(report.environment.prover)}</code></li>
        </ul>
      </article>
      <article class="card">
        <h2>Summary</h2>
        <ul>
          <li>Passed gates: ${report.summary.passed}</li>
          <li>Failed gates: ${report.summary.failed}</li>
          <li>Skipped gates: ${report.summary.skipped}</li>
          <li>Indexed deposits: ${report.evidence.indexedDeposits}</li>
          <li>Indexed attestations: ${report.evidence.indexedAttestations}</li>
          <li>Scenario JSON: ${escapeHtml(report.evidence.scenarioJsonPath ?? "n/a")}</li>
        </ul>
      </article>
    </section>

    <section style="margin-top: 18px;">
      <h2>Gate Results</h2>
      <table>
        <thead>
          <tr>
            <th>Gate</th>
            <th>Status</th>
            <th>Command</th>
            <th>Duration</th>
            <th>Details</th>
          </tr>
        </thead>
        <tbody>
          ${gateRows}
        </tbody>
      </table>
    </section>
  </div>
</body>
</html>`;
}

function parseArgs(argv: string[]): { input: string; output: string } {
  const values: Record<string, string> = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (!argv[i].startsWith("--")) continue;
    const key = argv[i].slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      values[key] = next;
      i += 1;
    }
  }

  const input = values.input;
  const output = values.output;
  if (!input || !output) {
    throw new Error("usage: tsx scripts/render-bridge-report.ts --input <json> --output <html>");
  }
  return { input, output };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    const args = parseArgs(process.argv.slice(2));
    const inputPath = path.resolve(args.input);
    const outputPath = path.resolve(args.output);
    const raw = fs.readFileSync(inputPath, "utf8");
    const report = JSON.parse(raw) as BridgeValidationReport;
    const html = renderBridgeReportHtml(report);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, html, "utf8");
    console.log(`Wrote HTML report to ${outputPath}`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
