# Adversarial review evidence

Date: 2026-10-07. Status: in progress.

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
- Stake reward allocations could exceed funding, sweeps could drain principal, and exit accounting mixed rewards with principal. Separate accrued liability tracking and solvent payouts were added.
- Claim leaf hashing repeated a struct field. Structured ABI encoding now commits each field.
- Token deposits trusted nominal transfer amounts. Exact received amounts are required.
- Docker published privileged development services on all host interfaces. Published bindings now use loopback.
- Permissive node-manager CORS allowed arbitrary browser origins to reach owner operations. An explicit configured local UI policy and request rejection were added.
- Tracked compiled web files duplicated maintained TypeScript/Vue and could shadow configuration. They were removed; typechecking now uses noEmit.

## Verification in progress

The proof crate's initial focused suite passed 45 tests. A dependency-free parser harness passed 15 tests; restoring the original parser caused both new security regressions to fail. The complete Foundry suite passed 111 tests with none skipped and 1,000 runs per fuzz test. A shared ABI golden vector was consumed by both Rust and Solidity to check settlement with zero honest attestations. Contract claim-commitment and exit-conservation fuzz campaigns passed 1,000 runs each; restoring the original hash or sweep caused their regressions to fail. The indexer codegen/build and three handler tests pass. Root typechecking and two compose tests pass. GitHub UI, formatting and PR-policy checks pass; broader Rust and dependency checks remain pending. Clean-checkout CI exposed missing Solidity submodule gitlinks and missing generated chain metadata; both now have reproducible inputs.

## Limitations

The guest uses witness-selected receipt roots, event expectations and a subset of deposit receipts. These do not independently identify canonical contracts, real chain history or a complete latest block root. The RPC method named finalisedHeader does not enforce finality for numbered requests. The mock runtime does not demonstrate genuine proof soundness.

The accounting and corrected claim commitment require fresh local deployments or a separately reviewed migration. No performance or cryptographic assurance claim follows from this review. Exact final commands and results will be recorded after CI completes.
