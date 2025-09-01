# SP1POC  BN254 BLS PoP Vector Generator (SolBLS-compatible)

This POC tool generates BLS key material and proof-of-possession (PoP) test vectors for use with the [`solbls`](https://github.com/warlock-labs/solbls) Solidity library. It produces, per wallet address:

* a BN254 secret key (hex),
* a G2 public key serialized for Solidity as `[x_re, x_im, y_re, y_im]`,
* the PoP message `abi.encodePacked(pk_limbs, msg.sender)`,
* the hash-to-curve result `H(msg)` on G1 (SVDW after `expand_message_xmd(Keccak256, 96)`)
* a G1 signature on `H(msg)`
* a local pairing check to sanity-verify `e(sig, G2) == e(H(msg), pk)`.

### Why this matches SolBLS

* SolBLS uses RFC 9380’s `expand_message_xmd` and Shallue–van de Woestijne (SVDW) mapping for BN254. This tool follows the same pipeline.
* On-chain verification goes through the BN254 precompiles (EIP-196/197). We serialize the Fp² limbs in the `[x_re, x_im, y_re, y_im]` layout expected by typical Solidity-side checks before the arguments are swapped for the precompile call.
* `Keccak256` (Ethereum’s “sha3”) is selected from the Rust `sha3` crate; it is distinct from the standardized `SHA3-256`.


## What the code does

At a high level, for each address in `wallets`:

1. Generate a BN254 BLS keypair with Sylow.
2. Serialize `pk ∈ G2` to `[x_re, x_im, y_re, y_im]`.
3. Build the PoP message `m = abi.encodePacked(pk_limbs, address)`.
4. Compute `H(m) ∈ G1` using RFC 9380 `expand_message_xmd(Keccak256, 96)` then SVDW mapping.
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

## How to run

Use this exact invocation to avoid workspace lock contention (see next section):

```bash
CARGO_HOME=/tmp/cargo-$USER-$$ \
cargo run --package bls-keygen --bin bls-keygen --release
```

This will print a generator sanity check and write `bls_test_data.json` with one object per address.


## Developer notes

*Why set `CARGO_HOME=/tmp/cargo-$USER-$$`?*

Cargo uses a **global “Cargo home”** to cache the registry index and crate sources (typically `~/.cargo`). Multiple processes (for example, VS Code tasks, rust-analyzer background builds, or a second terminal) can compete for **locks** in that shared location during updates/compilations, which may stall CI or local scripts.

By setting `CARGO_HOME` to a **unique, per-process directory** (`/tmp/cargo-$USER-$$`), you isolate each run’s cache so it doesn’t contend with an existing IDE build or another shell, avoiding lock waits. See Cargo’s documentation for `CARGO_HOME` and the function of the Cargo home cache.

