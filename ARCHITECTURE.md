# Bridge architecture

## State and ownership

The source `Bridge` owns deposited assets and its incremental exit tree. The destination `Bridge` owns liquidity and consumed claims. `ValidatorManager` owns validator membership, submitted attestations, pre-confirmed roots and settlement replay tracking. `StakeManager` owns principal, reward reserves and validator withdrawals.

The indexer is a derived event view. Rust validators obtain receipts and trie proofs from `chain-manager`, validate the deposit event and submit attestations. `node-manager` issues certificates using the configured owner and performs owner operations. Neither indexer rows nor certificates establish chain consensus.

## Proof boundary

`bridge-script` builds `ZkvmInput` from RPC and indexer data. `bridge-program` verifies receipt inclusion under supplied receipt roots, extracts deposit and attestation events, compares roots and ABI-encodes public settlement values. `ValidatorManager` consumes those values through its configured SP1 verifier and program key.

The guest does not authenticate supplied receipt roots to a consensus-verified header chain. Host header hashes are witness metadata, not an independently trusted anchor. A malicious host can supply a self-consistent artificial receipt trie. Genuine SP1 proving alone therefore cannot establish that the events happened on Ethereum or Base. This boundary needs an authenticated chain anchor and binding of chain, block, bridge address and program output before production use.

The `chain-manager` method named `finalisedHeader` currently fetches the requested RPC block tag or number. A numbered block is not checked against a finality checkpoint; the name does not guarantee finality.

The local runtime sets `SP1_PROVER=mock`. Its tests can exercise host orchestration and contract state changes but do not demonstrate cryptographic proof soundness.

## Fast claims and administrative authority

Destination claims rely on pre-confirmed roots and available destination liquidity. Validator quorum is counted by active validators. This model depends on membership synchronisation and honest validator participation; it does not implement a general cross-chain light client.

The owner can configure managers and upgrade proxies. Local certificate and reward endpoints exercise that authority using development keys. Treat the machine and its local processes as trusted during this experiment.

## Failure and resource boundaries

RPC failures, missing receipt proofs or invalid receipts must prevent the corresponding settlement or attestation. Claims are consumed atomically with transfers. Deposits must account for assets actually received. Reward allocations must remain backed by reserves; withdrawing principal must preserve reward liabilities.

An operational interruption can leave a deposit awaiting validators or settlement. This prototype does not provide a production recovery or emergency governance mechanism. Indexer availability and RPC finality behaviour remain external dependencies.
