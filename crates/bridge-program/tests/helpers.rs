/// Shared RLP encoding helpers for bridge-program tests.
/// These mirror the encoding rules in mpt.rs to build consistent test data.

pub fn rlp_string(payload: &[u8]) -> Vec<u8> {
    if payload.len() == 1 && payload[0] <= 0x7f {
        return payload.to_vec();
    }
    let mut out = Vec::new();
    if payload.len() <= 55 {
        out.push(0x80 + payload.len() as u8);
    } else {
        let len_bytes = encode_length(payload.len());
        out.push(0xb7 + len_bytes.len() as u8);
        out.extend_from_slice(&len_bytes);
    }
    out.extend_from_slice(payload);
    out
}

pub fn rlp_list(items_payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    if items_payload.len() <= 55 {
        out.push(0xc0 + items_payload.len() as u8);
    } else {
        let len_bytes = encode_length(items_payload.len());
        out.push(0xf7 + len_bytes.len() as u8);
        out.extend_from_slice(&len_bytes);
    }
    out.extend_from_slice(items_payload);
    out
}

fn encode_length(len: usize) -> Vec<u8> {
    let mut v = len;
    let mut bytes = vec![];
    while v > 0 {
        bytes.push((v & 0xff) as u8);
        v >>= 8;
    }
    bytes.reverse();
    bytes
}

pub fn concat(slices: &[Vec<u8>]) -> Vec<u8> {
    slices.iter().flat_map(|s| s.iter().copied()).collect()
}

/// Build an RLP-encoded receipt with one log.
/// Receipt: RLP([status=1, cumGasUsed=21000, logsBloom=256zeros, logs=[log]])
/// Log: RLP([address_20bytes, [topic0, topic1, topic2, topic3], data])
pub fn build_receipt_with_log(
    log_address: [u8; 20],
    topics: &[[u8; 32]],
    log_data: &[u8],
) -> Vec<u8> {
    let encoded_topics: Vec<Vec<u8>> = topics.iter().map(|t| rlp_string(t)).collect();
    let topics_payload = concat(&encoded_topics);
    let topics_list = rlp_list(&topics_payload);

    let log_payload = concat(&[rlp_string(&log_address), topics_list, rlp_string(log_data)]);
    let log_encoded = rlp_list(&log_payload);

    let logs_payload = log_encoded;
    let logs_list = rlp_list(&logs_payload);

    let bloom = [0u8; 256];
    let gas_used: u64 = 21000;
    let gas_used_bytes: Vec<u8> = {
        let b = gas_used.to_be_bytes();
        b.iter().skip_while(|&&x| x == 0).copied().collect()
    };

    let receipt_payload = concat(&[
        rlp_string(&[0x01]),         // status
        rlp_string(&gas_used_bytes), // cumGasUsed
        rlp_string(&bloom),          // logsBloom
        logs_list,                   // logs
    ]);
    rlp_list(&receipt_payload)
}

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
