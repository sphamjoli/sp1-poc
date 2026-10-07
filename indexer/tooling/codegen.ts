import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

type JsonObject = Record<string, unknown>;
type DependencyOverrides = Record<string, string>;

const indexerDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const generatedDirectory = path.join(indexerDirectory, "generated");
const runtimeLockPath = path.join(indexerDirectory, "generated-runtime.pnpm-lock.yaml");

function parseObject(value: unknown, label: string): JsonObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${label} must contain a JSON object`);
  }
  return value as JsonObject;
}

function readObject(file: string): JsonObject {
  const value: unknown = JSON.parse(fs.readFileSync(file, "utf8"));
  return parseObject(value, file);
}

function parseOverrides(value: unknown): DependencyOverrides {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("generatedRuntimeOverrides must contain a package/version map");
  }
  const overrides: DependencyOverrides = {};
  for (const [name, version] of Object.entries(value)) {
    if (typeof version !== "string" || version.length === 0) {
      throw new Error(`generated runtime override ${name} has an invalid version`);
    }
    overrides[name] = version;
  }
  return overrides;
}

function runPnpm(argumentsList: string[], cwd: string): void {
  const result = spawnSync("pnpm", argumentsList, {
    cwd,
    shell: false,
    env: { ...process.env, CI: "true" },
    stdio: "inherit",
    timeout: 600_000,
  });
  if (result.error) throw new Error("Indexer package command failed", { cause: result.error });
  if (result.status !== 0) throw new Error(`pnpm ${argumentsList[0]} failed with exit ${result.status}`);
}

function main(): void {
  const argumentsList = process.argv.slice(2);
  if (argumentsList.length > 1 || (argumentsList.length === 1 && argumentsList[0] !== "--update-lock")) {
    throw new Error("Usage: codegen.ts [--update-lock]");
  }
  const updateLock = argumentsList[0] === "--update-lock";
  if (!updateLock && !fs.existsSync(runtimeLockPath)) {
    throw new Error("Generated runtime lock is missing; review and run codegen:update-lock first");
  }

  runPnpm(["exec", "envio", "codegen"], indexerDirectory);
  const source = readObject(path.join(indexerDirectory, "package.json"));
  const generated = readObject(path.join(generatedDirectory, "package.json"));
  generated.packageManager = "pnpm@10.17.1";
  generated.pnpm = {
    overrides: {
      ...parseOverrides(parseObject(source.pnpm, "indexer pnpm policy").overrides),
      ...parseOverrides(source.generatedRuntimeOverrides),
    },
    onlyBuiltDependencies: ["rescript"],
  };
  fs.writeFileSync(path.join(generatedDirectory, "package.json"), JSON.stringify(generated, null, 2) + "\n");

  if (updateLock) {
    runPnpm(["install", "--lockfile-only"], generatedDirectory);
    fs.copyFileSync(path.join(generatedDirectory, "pnpm-lock.yaml"), runtimeLockPath);
  } else {
    fs.copyFileSync(runtimeLockPath, path.join(generatedDirectory, "pnpm-lock.yaml"));
  }
  runPnpm(["install", "--frozen-lockfile"], generatedDirectory);
  runPnpm(["audit"], generatedDirectory);
  runPnpm(["run", "build"], generatedDirectory);
}

main();
