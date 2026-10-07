# Chain manager

The Rust RPC service provides headers, receipts and receipt-trie proofs for configured chains. Validators and the SP1 host consume those results.

The method named `finalisedHeader` fetches the requested RPC block tag or number. It does not check a numbered block against a finality checkpoint. Its output must not be treated as a consensus-authenticated chain anchor. See [the proof boundary](../../ARCHITECTURE.md#proof-boundary).

Run it through the root [local stack](../../README.md) so generated configuration, deployments and RPC addresses agree. Use `bash scripts/check.sh rust` from the repository root for shared Rust checks.
