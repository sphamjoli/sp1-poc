# Bridge event indexer

Envio indexes bridge deposits, claims and validator events into a GraphQL view for the Rust services and UI. Its rows are derived data; receipt proofs and contract state establish the relevant on-chain facts.

## Install and verify

Use Node.js 22 or later, pnpm 10.17.1 for Envio's generated local package, and Bun 1.4.2 to run project commands.

```bash
pnpm install --frozen-lockfile
bun run codegen
bun run build
bun run mocha
```

Code generation follows `config.yaml` and `schema.graphql`. Generated code stays out of Git.

Run the full local system through the root [README](../README.md); runtime generation synchronises contract addresses and indexer ports. The development GraphQL secret is `testing`. Keep its published endpoint on loopback and use only development assets.
