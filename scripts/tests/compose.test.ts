import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { buildComposeFile } from "../generate-stack-compose.ts";
import { loadRuntimeConfig } from "../runtime-config-lib.ts";

test("published stack ports remain on loopback and container connections remain reachable", () => {
  const config = loadRuntimeConfig("config/runtime.local.json");
  config.indexer.hasura_secret = "secret${HOME}\n: # YAML";
  const compose = buildComposeFile(config, "config/runtime.local.json");
  const mappings = [...compose.matchAll(/- "([^"\n]+:\d+)"/g)].map((match) => match[1]);
  assert.equal(mappings.length, config.chains.length + 5);
  for (const mapping of mappings) assert.match(mapping, /^127\.0\.0\.1:\d+:\d+$/);
  assert.match(compose, /CHAIN_MANAGER_BIND: "0\.0\.0\.0:/);
  assert.match(compose, /NODE_MANAGER_BIND: "0\.0\.0\.0:/);
  assert.ok(compose.includes('"secret$${HOME}\\n: # YAML"'));
  assert.match(compose, /RPC_URL_31338: "http:\/\/anvil-31338:/);
});

test("validator catalog rejects YAML injection and malformed runtime values", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "sp1-compose-"));
  const catalog = path.join(directory, "validators.json");
  try {
    const config = loadRuntimeConfig("config/runtime.local.json");
    config.validators_path = catalog;
    for (const entry of [null, 1, {}, { name: 123 }, { name: "alice\n  attacker:" }, { name: "../alice" }, { name: "" }]) {
      fs.writeFileSync(catalog, JSON.stringify([entry]));
      assert.throws(() => buildComposeFile(config, "config/runtime.local.json"), /invalid service name/);
    }
    fs.writeFileSync(catalog, JSON.stringify([{ name: "alice" }, { name: "alice" }]));
    assert.throws(() => buildComposeFile(config, "config/runtime.local.json"), /duplicate names/);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
