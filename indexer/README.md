# Bridge event indexer

Envio indexes bridge deposits, claims and validator events into a GraphQL view for the Rust services and UI. Its rows are derived data; receipt proofs and contract state establish the relevant on-chain facts.

## Install and verify

Use Node.js 22 or later, pnpm 10.17.1 for Envio's generated local package, and Bun 1.4.2 to run project commands.

From the `indexer` directory:

```bash
pnpm install --frozen-lockfile
(cd .. && bun scripts/generate-chain-metadata.ts)
bun run codegen
bun run build
bun run mocha
```

Code generation follows `config.yaml` and `schema.graphql`. Generated code stays out of Git.

Run the full local system through the root [README](../README.md); runtime generation synchronises contract addresses and indexer ports. The development GraphQL secret is `testing`. Keep its published endpoint on loopback and use only development assets.

The Docker image uses the repository root as its build context. From the repository root, run:

```sh
docker build --file indexer/Dockerfile --tag sp1-indexer .
```

The image generates chain labels from `config/chains` with the same TypeScript helper used by local checks. It then generates the Envio runtime, installs its reviewed lockfile, audits the dependencies, and compiles the runtime. Local generated files are excluded from the build context.

For the indexer service stack, run `docker compose -f indexer/docker-compose.yaml up --build` from the repository root.
