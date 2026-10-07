# Adversarial review evidence

Date: 2026-10-07. Local validation complete; GitHub CI must pass before merge.

## Scope and method

An AI-assisted review examined owned Rust proof/runtime code, Solidity bridge and stake contracts, web build outputs, CI and hooks. Independent adversarial agents reviewed Rust, contracts and automation. Findings require code evidence and regression checks; a green suite alone does not establish security.

The engineering guidance was read end to end from the global `solid-dry-kiss/SKILL.md`. The `academic-research-skills/deep-research/SKILL.md` was also read end to end; its fact-checking and limitation rules were applied to technical claims. This is a code review, not a systematic literature review or an independent security audit.

## Assumptions and QA plan

| Assumption | Risk | Evidence and required check |
|---|---|---|
| Receipt roots correspond to genuine chain history | Fabricated settlement witnesses | Observed: roots are host inputs; no guest consensus anchor. Document limitation and check batch binding. |
| Malformed RLP cannot crash the parser | Proof input denial of service | Boundary tests for oversized, truncated and non-canonical lengths. |
| Rewards and sweeps preserve principal and pending rewards | Insolvency | Contract regression tests for reserve allocation, repeated sweep and exits. |
| Token deposits equal amounts recorded | Underfunded bridge claims | Tests for fee-on-transfer assets and unintended ETH. |
| Web JavaScript is maintained source | Incorrect GitHub language and stale runtime code | Inspect adjacent emitted JS, remove generated outputs and build without source emissions. |
| Development owner endpoints are local | Unauthorised owner transactions | Check published Docker host bindings and test compose generation. |

## Primary references

- [Ethereum RLP encoding](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/): canonical encoding and length rules used to assess malformed parser inputs.
- [GitHub Linguist overrides](https://github.com/github-linguist/linguist/blob/main/docs/overrides.md): generated and vendored code are excluded from language statistics.

## Observed findings

- RLP lengths used unchecked arithmetic and accepted non-canonical encodings. Checked arithmetic and canonicality checks now reject those inputs.
- Trie nodes accepted trailing bytes and invalid compact-path flags. Exact consumption and path encoding checks were added.
- Public settlement chain/block selection was not tied to the deposit batch; repeated attestation witnesses could amplify slashing. Batch checks and duplicate rejection were added.
- Validator receipt verification did not bind the deposit emitter to the deployed source bridge. It now checks the configured emitter, exact event shape, canonical address padding and checked integer conversions.
- Both validator and guest receipt handling stopped at the first bridge deposit, rejecting later deposits in a legitimate multicall. They now search for the full expected event; generated receipt-position properties cover matching, foreign, malformed and absent candidates at the relevant boundaries.
- Stake reward allocations could exceed funding, sweeps could drain principal, and exit accounting mixed rewards with principal. Separate accrued liability tracking and solvent payouts were added.
- Claim leaf hashing repeated a struct field. Structured ABI encoding now commits each field.
- Token deposits trusted nominal transfer amounts. Exact received amounts are required.
- Docker published privileged development services on all host interfaces. Published bindings now use loopback.
- Permissive node-manager CORS allowed arbitrary browser origins to reach owner operations. An explicit configured local UI policy and request rejection were added.
- Tracked compiled web files duplicated maintained TypeScript/Vue and could shadow configuration. They were removed; typechecking now uses noEmit.
- The remaining owned JavaScript configuration was replaced by TypeScript in `vite.config.ts`. PostCSS versions were aligned so its plugin and Vite share compatible types.
- Runtime tests assumed locally generated deployment files, and an indexer image could inherit ignored chain metadata from a developer checkout. Tests now own deployment fixtures; the image generates metadata from the canonical checked-in chain configuration.
- Docker and Makefile installers used older or floating tool versions. They now share the reviewed SP1 installer and pinned Rust, Foundry and Bun versions; OpenZeppelin's Docker validator uses its locked local dependency through Bun.

## Test ownership

Empty public fixture getters were incorrectly counted as Foundry tests. They are now internal. An inherited token configuration test runs once in its owning suite; deposit state and same-chain rejection assertions use their existing fuzz campaigns rather than duplicate examples. Conservation assertions were added to the existing campaign. Tests for insertion and duplicate-key rejection exercise distinct outcomes, despite their similar names.

## Verification

The complete final Foundry gate passed 89 tests with none failed or skipped and 1,000 runs in each of 11 fuzz campaigns. A shared ABI golden vector was consumed by both Rust and Solidity to check settlement with zero honest attestations. Restoring the original claim hash or sweep caused their regressions to fail. A dependency-free parser harness passed 15 tests; restoring the original parser caused both new security regressions to fail. Restoring the missing validator emitter check also caused its property test to fail. The indexer codegen/build and three handler tests pass. Root typechecking, two compose tests, the TypeScript UI build, 17 UI unit tests and one browser journey pass.

`bash scripts/check.sh rust` passes: stable formatting, whole-workspace Clippy with all targets/features and warnings denied, 90 workspace tests, 54 focused guest tests without the default zkVM feature, the real SP1 cross-build, and strict workspace rustdoc. These are different feature configurations of shared tests, not duplicate test definitions. The canonical guest ELF at `target/elf-compilation/riscv32im-succinct-zkvm-elf/release/bridge-program` is 299,020 bytes with SP1 5.2.4 and its official succinct 1.91.1-dev compiler. Workspace feature defaults now express the shared types' no-std compatibility explicitly, and library and binary crate overviews satisfy the existing documentation lint.

Restoring first-candidate early rejection made the new guest receipt-position property fail with a minimal counterexample at position 1. The restored corrected source passed that property; no mutation-only regression artifact remains.

Both indexer dependency graphs, root and web audit cleanly. OpenZeppelin tooling has one narrowly scoped expiring exception; RustSec reports no vulnerability entries but still reports upstream unsoundness and maintenance warnings. See [the dependency review](dependency-audit.md) for exact advisories, call paths and limits. These warnings are not ignored.

Clean-checkout checks exposed missing Solidity submodule gitlinks and missing generated chain metadata; both now have reproducible inputs. A tracked-source-only indexer image builds, audits cleanly and passes its three handler tests. The runtime toolchain stage and both Foundry images build; offline checks confirm their exact tool versions. The Docker contract validator rejects arbitrary package installation. The full runtime release image was not compiled during this review. Final GitHub CI is tracked in [PR #3](https://github.com/sphamjoli/sp1-poc/pull/3); merging requires every check to succeed.

## Limitations

The guest uses witness-selected receipt roots, event expectations and a subset of deposit receipts. These do not independently identify canonical contracts, real chain history or a complete latest block root. The RPC method named finalisedHeader does not enforce finality for numbered requests. The mock runtime does not demonstrate genuine proof soundness.

The accounting and corrected claim commitment require fresh local deployments or a separately reviewed migration. No performance or cryptographic assurance claim follows from this review. The PR check records are the final evidence for the merged commit's CI results.
