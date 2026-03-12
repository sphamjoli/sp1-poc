mod helpers;
use alloy_primitives::keccak256;
use bridge_program::mpt::verify_receipt_inclusion;
use sp1_types::ProgramError;

// ---- helpers ----

/// Build a single-leaf MPT proof for a given receipt_envelope at tx_index 0.
/// Returns (receipts_root, proof_nodes).
fn single_leaf_proof(receipt_envelope: &[u8]) -> (alloy_primitives::B256, Vec<Vec<u8>>) {
    helpers::build_single_leaf_mpt(receipt_envelope)
}

// ---- happy path ----

#[test]
fn verify_single_leaf_tx0() {
    let receipt_envelope = vec![0x01u8]; // simplest possible "receipt"
    let (root, proof) = single_leaf_proof(&receipt_envelope);
    verify_receipt_inclusion(root, 0, &receipt_envelope, &proof).unwrap();
}

#[test]
fn verify_single_leaf_longer_receipt() {
    // A slightly longer receipt: 5 bytes
    let receipt_envelope = vec![0x01u8, 0x02, 0x03, 0x04, 0x05];
    let (root, proof) = single_leaf_proof(&receipt_envelope);
    verify_receipt_inclusion(root, 0, &receipt_envelope, &proof).unwrap();
}

// ---- error paths ----

#[test]
fn empty_proof_returns_error() {
    let receipt_envelope = vec![0x01u8];
    let root = keccak256(b"any");
    let result = verify_receipt_inclusion(root, 0, &receipt_envelope, &[]);
    assert_eq!(result, Err(ProgramError::ProofIsEmpty));
}

#[test]
fn wrong_root_returns_error() {
    let receipt_envelope = vec![0x01u8];
    let (_, proof) = single_leaf_proof(&receipt_envelope);
    let wrong_root = keccak256(b"wrong");
    let result = verify_receipt_inclusion(wrong_root, 0, &receipt_envelope, &proof);
    assert_eq!(result, Err(ProgramError::ProofRootMismatch));
}

#[test]
fn wrong_leaf_value_returns_error() {
    let receipt_envelope = vec![0x01u8];
    let (root, proof) = single_leaf_proof(&receipt_envelope);
    let different_envelope = vec![0x02u8];
    let result = verify_receipt_inclusion(root, 0, &different_envelope, &proof);
    assert_eq!(result, Err(ProgramError::TrieLeafValueMismatch));
}

#[test]
fn wrong_tx_index_returns_error() {
    // Proof is for tx_index=0 but we ask for tx_index=1 → path mismatch
    let receipt_envelope = vec![0x01u8];
    let (root, proof) = single_leaf_proof(&receipt_envelope);
    let result = verify_receipt_inclusion(root, 1, &receipt_envelope, &proof);
    // key nibbles for index 1 differ from the leaf's compact path → TriePathMismatch
    assert!(result.is_err());
}
