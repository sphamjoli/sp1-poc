# Development dependency advisory review

Reviewed: 2026-10-07. Review expires: 2026-11-07.

## OpenZeppelin upgrade validator

The contract package pins `@openzeppelin/upgrades-core` 1.46.0, which reaches `elliptic` 6.6.1 through `ethereumjs-util`, `ethereum-cryptography` and `secp256k1`. [GHSA-848j-6mx2-7j84](https://github.com/advisories/GHSA-848j-6mx2-7j84) identifies risky cryptographic primitives, and the package audit reports no published fixed version.

The validator is a development tool that analyses compiler build metadata. Inspection of every `ethereumjs-util` call in the installed validator found only `keccak256` and `toChecksumAddress`, in `eip-1967`, `version`, `utils/erc7201`, `call-optional-signature` and `utils/address`. It does not invoke the imported library's `ecsign` or `ecrecover` functions, the paths that reach secp256k1 signing and recovery. No production runtime or browser dependency imports this package. Keeping the upgrade validator provides storage-layout checks that would be lost by removing it.

`scripts/audit-dependencies.sh` accepts only this advisory for the contract tool package, requires the exact reviewed validator and elliptic versions, and fails when the review expires. Root and browser packages receive no exception. Every other advisory remains a failure. Re-review the exception before changing the validator, calling a signing API, processing untrusted upgrade metadata, or reaching the expiry date. This acceptance does not justify using elliptic for production signing.

## Browser build tools

Tailwind 3 depended on the unpatched `braces` glob parser. The browser package now uses Tailwind 4.3.3 and its official PostCSS plugin, retaining the existing theme through `@config`. The browser test runner, Vue and viem were updated to patched versions. The reviewed esbuild override 0.28.1 replaces the affected Vite build dependency; the production build and browser checks exercise this combination. Browser audits have no suppression.

## Indexer and generated runtime

The owned indexer lock originally reported 43 advisories. Mocha 11.8.0 and ts-mocha 11.1.0 remove the unpatched Chokidar 3 `braces` path; patched same-family overrides cover the remaining Envio 2.25.0 and test-runner dependencies. The Mocha reporter uses jsdiff's `createPatch`, which remains available in the reviewed 8.0.4 override. The serializer 7.1.2 override preserves the reporter's function-serialisation interface. Handler compilation and event tests verify these combinations. There are no indexer advisory exceptions.

Envio generates an independent runtime package with pinned older dependencies and an unlocked installation. Auditing that separate graph found 37 advisories, including critical `shell-quote` and `proxy-addr` findings. `indexer/tooling/codegen.ts` now reapplies the source-owned policy after code generation, installs the reviewed `indexer/generated-runtime.pnpm-lock.yaml` with `--frozen-lockfile`, audits it and rebuilds the generated runtime. The runtime retains Envio 2.25.0 and its handler APIs; Express 4 and the affected same-major transitive dependencies receive patched versions. Only ReScript's necessary compiler installation script is allowed.

Ordinary `bun run codegen` fails if the reviewed runtime lock is absent or no longer matches the generated manifest. Use `bun run codegen:update-lock` only when deliberately reviewing a dependency update, then inspect and commit the source lock. The initial Envio generator installation remains upstream behaviour; the wrapper audits and rebuilds the final dependency graph before the generated runtime is used. Both owned and generated-runtime audits currently report no known vulnerabilities. These checks establish dependency advisory coverage and compilation, not live indexer/network or database compatibility under production load.

The indexer Docker image includes Bun 1.4.2 alongside Node.js 22 and routes generation through the same wrapper. The required indexer CI job audits the final generated runtime explicitly before compiling and testing the handlers.

## Rust dependency remediation and remaining upstream soundness issues

The committed graph now pins the SP1 SDK, build helper and guest runtime to exactly 5.2.4. SDK default features are disabled: this project uses local CPU/mock proving and does not use the remote network prover. Unlike 5.2.1, official 5.2.4 makes AWS dependencies optional; disabling the network defaults removes the legacy AWS, Hyper 0.14, h2 0.3 and rustls 0.21 graph. MongoDB 3.7.0 preserves SRV URL support while replacing the affected Hickory 0.24 resolver. Compatible lock updates patch bytes, ruint, time, alloy-dyn-abi, quinn-proto, crossbeam-channel, modern h2/rustls/webpki, anyhow, keccak and both rand families. serial_test 3.5.0 removes the affected scc dependency.

Official `sp1-cli` 5.2.4 source selects guest toolchain tag `succinct-1.91.1`; `sp1-build` 5.2.4 still targets `riscv32im-succinct-zkvm-elf`. This supports ruint 1.20.1's Rust 1.90 minimum without an unsupported MSRV override. CPU/mock client builder APIs remain present. Guest build and host tests must pass independently: advisory resolution alone does not demonstrate compatibility or proof correctness.

The final local `cargo audit --no-fetch --json` run on 2026-10-07 reports **0 vulnerabilities, 4 unsound warnings, 7 unmaintained warnings and 1 yanked package**. No Rust advisory is ignored. The initial graph reported 24 vulnerabilities. Cargo audit classifies the following memory-safety advisories as informational; its successful exit status does not mean they are fixed.

| Remaining soundness advisory | Dependency paths | Affected operation and observed exposure |
| --- | --- | --- |
| [RUSTSEC-2026-0253](https://rustsec.org/advisories/RUSTSEC-2026-0253.html), fixed in lru >=0.18.2 | sp1-sdk → sp1-prover 5.2.4 → lru 0.12.5; alloy-provider 1.1.2 → lru 0.13.0 | `LruCache::pop` can leave dangling pointers if a stored key's destructor panics and execution continues after unwinding. SP1's `recursion_program` cache uses `get` and `put`, with no observed cache `pop` call. Alloy's block stream calls `known_blocks.pop(&next_yield)`, but its key is `BlockNumber` (u64), which has no panicking destructor. No owned code calls the block-watch/cache-layer APIs. These observations narrow the demonstrated exposure; they do not repair the library. |
| [RUSTSEC-2026-0002](https://rustsec.org/advisories/RUSTSEC-2026-0002.html), fixed in lru >=0.16.3 | The same two paths, producing two further warnings | `IterMut::next`/`next_back` violate Stacked Borrows. No `iter_mut` use was found in the SP1 or Alloy cache consumers. SP1 recursive proof generation can use its cache during real local Groth16/PLONK proving; the development prover defaults to mock, but setting `SP1_PROVER` to another value selects CPU proving. Mock defaults therefore do not justify dismissing the dependency. |

SP1 5.2.4 requires lru ^0.12 and Alloy 1.1.2 requires ^0.13, so a compatible lock update cannot select the fixed major versions. The inspected latest Alloy 1.x (1.8.3) still requires lru ^0.16 and does not eliminate the panic-safety advisory. Alloy 2.x requires a newer Rust compiler than the reviewed host/guest pair. This review retains the compatible family rather than introducing an unreviewed fork or broad migration that leaves the issue unresolved. Upstream remediation or a separately tested migration is still required before claiming these soundness findings are fixed.

The seven maintenance warnings are ansi_term 0.12.1 (RUSTSEC-2021-0139), bincode 1.3.3 (RUSTSEC-2025-0141), derivative 2.2.0 (RUSTSEC-2024-0388), dotenv 0.15.0 (RUSTSEC-2021-0141), number_prefix 0.4.0 (RUSTSEC-2025-0119), paste 1.0.15 (RUSTSEC-2024-0436), and proc-macro-error2 2.0.1 (RUSTSEC-2026-0173). spin 0.9.8 is yanked and remains through lazy_static. These have not been blanket-suppressed or described as security clearance. Re-review the complete graph on dependency changes; the recorded counts are a dated observation, not a guarantee of production security.
