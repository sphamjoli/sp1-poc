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
