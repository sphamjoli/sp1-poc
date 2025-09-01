# bls-keygen — BN254 BLS PoP vector generator (SolBLS-compatible)

This tool generates BLS key material and proof-of-possession (PoP) test vectors for use with the [`solbls`](https://github.com/warlock-labs/solbls) Solidity library. It produces, per wallet address:

* a BN254 secret key (hex),
* a G2 public key serialized for Solidity as `[x_re, x_im, y_re, y_im]`,
* the PoP message `abi.encodePacked(pk_limbs, msg.sender)`,
* the hash-to-curve result `H(msg)` on G1 (SVDW after `expand_message_xmd(Keccak256, 96)`),
* a G1 signature on `H(msg)`,
* a local pairing check to sanity-verify `e(sig, G2) == e(H(msg), pk)`.

### Why this matches SolBLS

* SolBLS uses RFC 9380’s `expand_message_xmd` and Shallue–van de Woestijne (SVDW) mapping for BN254. This tool follows the same pipeline. ([GitHub][1], [IETF Datatracker][2])
* On-chain verification goes through the BN254 precompiles (EIP-196/197). We serialize the Fp² limbs in the `[x_re, x_im, y_re, y_im]` layout expected by typical Solidity-side checks before the arguments are swapped for the precompile call. ([docs.moonbeam.network][3], [Ethereum Research][4])
* `Keccak256` (Ethereum’s “sha3”) is selected from the Rust `sha3` crate; it is distinct from the standardized `SHA3-256`. ([Docs.rs][5], [Ethereum Stack Exchange][6])

---

## What the code does

At a high level, for each address in `wallets`:

1. Generate a BN254 BLS keypair with Sylow.
2. Serialize `pk ∈ G2` to `[x_re, x_im, y_re, y_im]`.
3. Build the PoP message `m = abi.encodePacked(pk_limbs, address)`.
4. Compute `H(m) ∈ G1` using RFC 9380 `expand_message_xmd(Keccak256, 96)` then SVDW mapping. ([IETF Datatracker][2])
5. Sign `H(m)` with the secret key.
6. Check `pairing(sig, G2_gen) == pairing(H(m), pk)` locally.
7. Emit a JSON file `bls_test_data.json` with the vectors.

### Data flow

```mermaid
flowchart TD
  A[Wallet address] -->|abi.encodePacked with pk| B[Message m]
  subgraph G2 serialization
    PkG2[pk in G2] -->|to_be_bytes| L[x.c0, x.c1, y.c0, y.c1]
    L -->|re/im reorder| S[[x_re, x_im, y_re, y_im]]
  end
  S --> B
  B --> C[expand_message_xmd(Keccak256, 96)]
  C --> D[SVDW map -> H(m) in G1]
  E[Secret key sk] --> F[Sign H(m)]
  D --> F
  F --> G[Signature in G1]
  D --> H[Pairing check]
  PkG2 --> H
  H --> I[Write JSON: sk, pk, H(m), sig]
```

---

## Example user story

* **Alice** operates an on-chain staking system that verifies BLS PoP with SolBLS.
* **Bob** maintains off-chain tooling that must precompute vectors for integration tests.
* **Charlie** audits the pipeline.

Steps:

1. Bob adds Alice’s known Anvil EVM test addresses to the `wallets` array.
2. Bob runs the command below to produce `bls_test_data.json`.
3. Alice’s Solidity tests import the emitted limbs and call the contract’s `hashToPoint(domain, m)` to confirm the on-chain `H(m)` matches, then `verifySingle(sig, pk, H(m))` succeeds.
4. Charlie compares the limb ordering against an EIP-197 reference (or Moonbeam/Kaia docs) to confirm real/imag layout and checks that RFC 9380 parameters are reflected (XMD, 96-byte output, Keccak). ([docs.moonbeam.network][3], [docs.kaia.io][7], [IETF Datatracker][2])

---

## How to run

Use this exact invocation to avoid workspace lock contention (see next section):

```bash
CARGO_HOME=/tmp/cargo-$USER-$$ \
cargo run --package bls-keygen --bin bls-keygen --release
```

This will print a generator sanity check and write `bls_test_data.json` with one object per address.

---

## Why set `CARGO_HOME=/tmp/cargo-$USER-$$`

Cargo uses a **global “Cargo home”** to cache the registry index and crate sources (typically `~/.cargo`). Multiple processes (for example, VS Code tasks, rust-analyzer background builds, or a second terminal) can compete for **locks** in that shared location during updates/compilations, which may stall CI or local scripts.

By setting `CARGO_HOME` to a **unique, per-process directory** (`/tmp/cargo-$USER-$$`), you isolate each run’s cache so it doesn’t contend with an existing IDE build or another shell, avoiding lock waits. See Cargo’s documentation for `CARGO_HOME` and the function of the Cargo home cache. ([Rust Documentation][8], [Docs.rs][9])

> Note: This is a pragmatic build isolation technique for developer workflows. For CI, consider a stable per-job cache path to keep dependency downloads efficient.

---

## References

* SolBLS (BN254 BLS for Solidity), background and design notes. ([GitHub][1])
* RFC 9380 “Hashing to Elliptic Curves” (expand\_message\_xmd, SVDW). ([RFC Editor][10], [IETF Datatracker][2])
* EVM BN254 precompiles and encoding expectations (EIP-196/197 overviews). ([docs.moonbeam.network][3], [Ethereum Research][4], [Qtum][11])
* Rust `sha3` crate: availability of `Keccak256` (pre-NIST padding). ([Docs.rs][5])
* Keccak vs SHA-3 distinction in Ethereum context. ([Ethereum Stack Exchange][6])
* Cargo home and `CARGO_HOME` environment variable. ([Rust Documentation][8])

---

### Outputs

* `bls_test_data.json`: array of objects

  * `private_key` — hex string (BN254 scalar)
  * `public_key` — `[x_re, x_im, y_re, y_im]` hex strings
  * `proof_of_possession` — signature `[x, y]` hex strings
  * `wallet_address`, `domain`, `message_hash` — for on-chain re-computation

These vectors are ready to paste into Solidity tests or fixtures that use SolBLS for PoP verification.
