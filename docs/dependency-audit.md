# Development dependency advisory review

Reviewed: 2026-10-07. Review expires: 2026-11-07.

## OpenZeppelin upgrade validator

The contract package pins `@openzeppelin/upgrades-core` 1.46.0, which reaches `elliptic` 6.6.1 through `ethereumjs-util`, `ethereum-cryptography` and `secp256k1`. [GHSA-848j-6mx2-7j84](https://github.com/advisories/GHSA-848j-6mx2-7j84) identifies risky cryptographic primitives, and the package audit reports no published fixed version.

The validator is a development tool that analyses compiler build metadata. Inspection of every `ethereumjs-util` call in the installed validator found only `keccak256` and `toChecksumAddress`, in `eip-1967`, `version`, `utils/erc7201`, `call-optional-signature` and `utils/address`. It does not invoke the imported library's `ecsign` or `ecrecover` functions, the paths that reach secp256k1 signing and recovery. No production runtime or browser dependency imports this package. Keeping the upgrade validator provides storage-layout checks that would be lost by removing it.

`scripts/audit-dependencies.sh` accepts only this advisory for the contract tool package, requires the exact reviewed validator and elliptic versions, and fails when the review expires. Root and browser packages receive no exception. Every other advisory remains a failure. Re-review the exception before changing the validator, calling a signing API, processing untrusted upgrade metadata, or reaching the expiry date. This acceptance does not justify using elliptic for production signing.

## Browser build tools

Tailwind 3 depended on the unpatched `braces` glob parser. The browser package now uses Tailwind 4.3.3 and its official PostCSS plugin, retaining the existing theme through `@config`. The browser test runner, Vue and viem were updated to patched versions. The reviewed esbuild override 0.28.1 replaces the affected Vite build dependency; the production build and browser checks exercise this combination. Browser audits have no suppression.
