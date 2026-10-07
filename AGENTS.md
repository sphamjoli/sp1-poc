# Repository engineering instructions

Read the owning crate or contract, public interface, tests, callers and locked dependencies before changing behaviour. Preserve unrelated work and submodule changes. Use evidence to distinguish observed behaviour from assumptions.

## Design and security

- Keep one owner for each protocol rule and mutable state. Prefer a focused concrete type unless a real behavioural boundary needs a trait.
- Validate untrusted receipts, encodings, RPC/indexer data, API bodies and configuration at their boundary. Reject non-canonical encodings and enforce resource bounds.
- Keep staking principal, reward funding and accrued liabilities distinct. Token movements must preserve solvency and use exact receipt checks.
- Changes to proofs, hashes, public values, storage or accounting need a design document and compatibility assessment before implementation.
- This prototype uses development keys, mock proving and unauthenticated guest receipt roots. Do not present it as production-ready or claim that a numbered RPC block is finalised.
- Do not silently weaken a check, ignore failed assertions or suppress a security finding to make CI green.

## Tests and checks

Run `bash scripts/check.sh syntax`, then the affected checks (`rust`, `web`, `indexer`, `contracts`). CI and pre-push use the same script. Rust checks require the pinned SP1 toolchain; contract tests require local fixture RPCs with Ethereum chain ID 1 and Base chain ID 8453. Use `ETH_RPC_URL` and `BASE_RPC_URL` to isolate fixtures from a running stack.

Test externally visible behaviour and failure boundaries. Use fuzz/property tests for input families and conservation rules. Do not add multiple example tests that repeat the same assertion. Keep a regression only when it identifies a distinct defect. For security-critical fixes, restore a relevant mutation temporarily and verify that the regression fails; restore source before completion.

Use Bun for root, contracts and web package installation and commands; retain the indexer's locked pnpm installation where its generated Envio package requires it. Use frozen locks. Do not commit generated JavaScript beside TypeScript/Vue, build outputs, runtime state or private secrets. GitHub language classification must accurately reflect owned source.

## Documentation and Git

Keep README focused on purpose, setup and use, with links to architecture, security and contributor instructions. No Mermaid diagrams in README. Use British English, complete public interface contracts and plain prose. Comments explain invariants, not ticket history.

Use conventional `type(scope): description` commit/PR titles and `.github/pull_request_template.md`. Record exact observed checks, migration effects and unresolved limitations. Merge only after every required CI check succeeds; do not use administrator bypasses.
