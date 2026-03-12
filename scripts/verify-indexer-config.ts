import fs from "node:fs";
import { createHash } from "node:crypto";
import { INDEXER_CONFIG_PATH, generateIndexerConfig } from "./update-indexer-config.ts";
import { loadRuntimeConfig, runtimeConfigPath } from "./runtime-config-lib.ts";

function sha256(data: string): string {
  return createHash("sha256").update(data, "utf8").digest("hex");
}

function normalize(text: string): string {
  return text.replace(/\r\n/g, "\n").trimEnd();
}

function main(): void {
  const runtimeConfig = loadRuntimeConfig(runtimeConfigPath());
  if (!fs.existsSync(INDEXER_CONFIG_PATH)) {
    throw new Error(`${INDEXER_CONFIG_PATH} not found - run \`make update-indexer-config\` first`);
  }

  const expected = normalize(generateIndexerConfig());
  const actual = normalize(fs.readFileSync(INDEXER_CONFIG_PATH, "utf8"));

  if (actual !== expected) {
    const expectedHash = sha256(expected);
    const actualHash = sha256(actual);
    throw new Error(
      [
        "indexer/config.yaml does not match the generated deployment addresses.",
        `deploy artifacts: ${runtimeConfig.deployments_dir}`,
        `expected sha256: ${expectedHash}`,
        `actual sha256:   ${actualHash}`,
        "Run `make update-indexer-config` to sync addresses before running scenarios.",
      ].join("\n"),
    );
  }

  console.log("Indexer config matches current deploy-out contract addresses.");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
