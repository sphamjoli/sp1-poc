import { serializeIndexerChains } from "./chain-metadata.ts";
import fs from "node:fs";
import path from "node:path";

const names: Record<number, string> = {};
for (const folder of fs.readdirSync("config/chains").sort()) {
  const config: unknown = JSON.parse(fs.readFileSync(path.join("config/chains", folder, "chain.json"), "utf8"));
  if (typeof config !== "object" || config === null || !("id" in config) || !("name" in config)
      || typeof config.id !== "number" || !Number.isSafeInteger(config.id) || config.id <= 0
      || typeof config.name !== "string" || !config.name.trim() || names[config.id] !== undefined) {
    throw new Error(`Invalid or duplicate chain metadata in ${folder}`);
  }
  names[config.id] = config.name;
}
fs.mkdirSync("indexer/src/generated", { recursive: true });
fs.writeFileSync("indexer/src/generated/chainMetadata.ts", serializeIndexerChains(
  Object.entries(names).map(([id, name]) => ({ id: Number(id), name })),
));
