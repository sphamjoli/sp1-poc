use crate::rlp_helpers::{concat, rlp_list, rlp_string};

/// Build a minimal single-leaf MPT proof for tx_index=0 with given receipt_envelope.
/// Returns (receipts_root, proof_nodes).
pub fn build_single_leaf_mpt(receipt_envelope: &[u8]) -> (alloy_primitives::B256, Vec<Vec<u8>>) {
    use alloy_primitives::keccak256;

    // key for tx_index=0: rlp_encode_u64(0) = [0x80]
    // nibbles([0x80]) = [8, 0]
    // Leaf compact path (even length=2, leaf bit): prefix_nibble=0x2 → first_byte=0x20
    // Encoded nibbles: [8,0] → byte 0x80
    // compact_path = [0x20, 0x80]
    let compact_path = [0x20u8, 0x80u8];

    let leaf_payload = concat(&[rlp_string(&compact_path), rlp_string(receipt_envelope)]);
    let leaf_node = rlp_list(&leaf_payload);

    let receipts_root = keccak256(&leaf_node);
    (receipts_root, vec![leaf_node])
}
