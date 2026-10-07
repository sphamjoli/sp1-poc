# Bind settlement output to the contract consumer

Status: accepted for the local prototype. Date: 2026-10-07.

## Observed incompatibility

The guest emitted every attestation witness into its public values, including records with an incorrect bridge root. The contract requires finalised attestation roots to equal validBridgeRoot. Consequently an honest proof of a mixed honest/dishonest batch could revert before slashing. Solidity test helpers filtered the bad participants and did not expose the producer/consumer mismatch.

## Required behaviour

The deposit batch chain and block must agree with the public chain and every attestation's source chain and block. Reject repeated attestation receipt identities before accumulating penalties. Compute equivocators from the original verified records, then remove equivocating validators from the honest finalisation list. Preserve the established ABI layout.

The honest output list must describe one root/state-root/block tuple consistent with the Solidity consumer. An all-equivocator batch can carry penalties without an honest root record; the empty list does not provide a finalised root key. This is a prototype limitation requiring a separate replay/anchor design before production use.

## Alternatives and verification

Changing the consumer to accept incorrect roots in its honest list was rejected because it weakens the root consistency invariant. Filtering only before proof construction was rejected because an untrusted prover could bypass host-side policy. The guest owns output classification.

Use valid synthetic receipt/trie witnesses for a mixed batch, decode the ABI output and check honest and slash records against the Solidity interface. Test numerical event fields beyond u64 without panic. Keep chain/block mismatches and duplicate identities as input-boundary properties. A real consensus anchor and canonical source-contract policy remain outside this correction and are explicitly recorded in SECURITY.md.

Changing guest behaviour changes its program verification key. Fresh local deployment generation must rebuild the guest and use its new key. Any existing deployment needs a reviewed program-key update together with the contract/storage migration decisions.
