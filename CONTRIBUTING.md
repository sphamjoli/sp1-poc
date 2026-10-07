# Contributing

The Rust workspace owns proof execution, validation and runtime services. Solidity contracts, the browser UI and Envio indexer have separate checks because they cross different trust boundaries. Use British English, describe current behaviour and failure cases, and keep code, tests and documentation consistent.

## Set up a checkout

Install Rust 1.92.0 (selected by `rust-toolchain`), the SP1 5.2.4 compiler, Foundry 1.3.5, Node.js 22 and Bun 1.4.2. Initialise the pinned submodules, then install locked dependencies:

```bash
git submodule update --init --recursive
bun install --frozen-lockfile
(cd apps/web && bun install --frozen-lockfile)
(cd contracts && bun install --frozen-lockfile)
corepack prepare pnpm@10.17.1 --activate
(cd indexer && pnpm install --frozen-lockfile)
(cd apps/web && bunx --no-install playwright install chromium)
bash scripts/install-hooks.sh
```

Bun manages the root, browser and contract tooling packages. Envio retains its existing pnpm lock and code-generation installation because its generated local package uses that workflow. Node.js remains required by third-party tool executables and OpenZeppelin's Foundry upgrade validator. The validator is installed locally at an exact version, so its library-owned `npx` invocation does not download a package during a test.

Do not commit compiler output beside browser source. TypeScript checks types with `noEmit`; Vite writes the browser bundle into ignored `dist/`. Never use the published development keys or local mock prover with real assets. Keep privileged development endpoints on loopback.

## Run checks

CI and the pre-push hook call the same check script. Run an individual group while editing, then the full gate before pushing:

```bash
bash scripts/check.sh syntax
bash scripts/check.sh rust
bash scripts/check.sh web
bash scripts/check.sh indexer
bash scripts/check.sh contracts
make ci
```

The Rust gate checks formatting, tests, Clippy, the SP1 guest cross-build and ELF size, and Rustdoc with the locked dependency graph. Host tests run before Clippy because a normal build creates the guest ELF embedded by the host binaries; SP1 deliberately skips guest compilation during Clippy. Keep this order so the host gate works in a fresh checkout. CI separates formatting, guest, host and documentation jobs, and writes their results in one CI summary. The web gate checks runtime scripts, security regressions, the production bundle, unit tests and the browser journey. The indexer gate regenerates bindings, compiles handlers and tests event resolution. The contract gate starts and cleans up two isolated local Anvil chains on ports 18545 and 18546, using chain IDs 1 and 8453 required by the checked-in BLS fixture, then performs a clean build and 1,000-run fuzz tests. Keep those ports available. No external RPC is required.

The commit hook checks staged whitespace, JSON and shell syntax, plus Rust formatting when Rust is staged. Commit messages and PR titles use `type(scope): description`, for example `fix(bridge): reject replayed claims`. Scopes are `proof`, `runtime`, `bridge`, `contracts`, `protocol`, `ui`, `indexer`, `docs`, `ci`, `deps`, `security` and `repo`. Supported types are `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `perf` and `revert`. Hooks verify files; they do not rewrite or stage them.

## Pull requests

Use the pull-request template to explain the problem, resulting behaviour, security invariant and observed verification results. Review invalid input, replay, authorisation, partial failure, resource bounds and dependency changes before style. Use property or fuzz tests when many examples exercise the same rule. Record unavailable checks and upstream dependency limitations rather than weakening gates to obtain a green result.

GitHub Actions use fixed action revisions, read-only permissions and frozen dependency installs. The security job audits dependency locks and scans tracked source for secrets, with narrowly documented exceptions for published development fixtures. It cannot establish production readiness or replace an independent cryptographic and economic review.

PR checks include secret scan, title convention, path labels and one summary comment. Label definitions synchronise on changes to `main`; issue forms collect a goal or a reproducible failure. Dependabot monitors GitHub Actions, Cargo, Bun and the pnpm indexer. These workflows use `pull_request` events and never execute PR code through `pull_request_target`.
