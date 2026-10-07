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
