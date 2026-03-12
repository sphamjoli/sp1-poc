extern crate alloc;
use crate::rlp::{list_items, parse_item};
use alloc::vec;
use alloc::vec::Vec;
use alloy_primitives::{keccak256, B256};
use sp1_types::{ProgramError, ProgramResult};

pub fn rlp_encode_u64(value: u64) -> Vec<u8> {
    if value == 0 {
        return vec![0x80];
    }

    let mut bytes = Vec::new();
    let mut v = value;
    while v > 0 {
        bytes.push((v & 0xff) as u8);
        v >>= 8;
    }
    bytes.reverse();

    if bytes.len() == 1 && bytes[0] <= 0x7f {
        return bytes;
    }

    let mut out = Vec::with_capacity(1 + bytes.len());
    out.push(0x80 + (bytes.len() as u8));
    out.extend_from_slice(&bytes);
    out
}

fn bytes_to_nibbles(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push((b >> 4) & 0x0f);
        out.push(b & 0x0f);
    }
    out
}

fn decode_compact_path(compact: &[u8]) -> ProgramResult<(Vec<u8>, bool)> {
    if compact.is_empty() {
        return Err(ProgramError::TriePathMismatch);
    }

    let first_nibble = (compact[0] >> 4) & 0x0f;
    let second_nibble = compact[0] & 0x0f;

    let is_leaf = (first_nibble & 0x2) != 0;
    let is_odd = (first_nibble & 0x1) != 0;

    let mut nibbles = Vec::new();
    if is_odd {
        nibbles.push(second_nibble);
        for &b in &compact[1..] {
            nibbles.push((b >> 4) & 0x0f);
            nibbles.push(b & 0x0f);
        }
    } else {
        for &b in &compact[1..] {
            nibbles.push((b >> 4) & 0x0f);
            nibbles.push(b & 0x0f);
        }
    }

    Ok((nibbles, is_leaf))
}

fn node_hash(node_rlp: &[u8]) -> B256 {
    keccak256(node_rlp)
}

fn child_ref_matches(child_ref: &[u8], child_node_rlp: &[u8]) -> bool {
    if child_ref.len() == 32 {
        node_hash(child_node_rlp).as_slice() == child_ref
    } else {
        child_ref == child_node_rlp
    }
}

/// Verify receipt inclusion in the receipts trie under (rlp(tx_index)).
pub fn verify_receipt_inclusion(
    receipts_root: B256,
    tx_index: u64,
    receipt_envelope: &[u8],
    proof_nodes_rlp: &[Vec<u8>],
) -> ProgramResult<()> {
    if proof_nodes_rlp.is_empty() {
        return Err(ProgramError::ProofIsEmpty);
    }

    let root_node = &proof_nodes_rlp[0];
    if node_hash(root_node) != receipts_root {
        return Err(ProgramError::ProofRootMismatch);
    }

    let key_rlp = rlp_encode_u64(tx_index);
    let key_nibbles = bytes_to_nibbles(&key_rlp);
    let mut key_pos = 0usize;

    for i in 0..proof_nodes_rlp.len() {
        let node_rlp = &proof_nodes_rlp[i];
        let (node_item, _) = parse_item(node_rlp, 0)?;
        if !node_item.is_list {
            return Err(ProgramError::TrieNodeShapeUnexpected);
        }

        let items = list_items(node_item.payload)?;
        if items.len() == 17 {
            if key_pos == key_nibbles.len() {
                if items[16].payload != receipt_envelope {
                    return Err(ProgramError::TrieLeafValueMismatch);
                }
                return Ok(());
            }

            let nib = key_nibbles[key_pos] as usize;
            key_pos += 1;

            let child_ref = items[nib].payload;
            if child_ref.is_empty() {
                return Err(ProgramError::TriePathMismatch);
            }

            if i + 1 >= proof_nodes_rlp.len() {
                return Err(ProgramError::ProofNodeMismatch);
            }

            let next_node = &proof_nodes_rlp[i + 1];
            if !child_ref_matches(child_ref, next_node) {
                return Err(ProgramError::ProofNodeMismatch);
            }
            continue;
        }

        if items.len() == 2 {
            let (path_nibbles, is_leaf) = decode_compact_path(items[0].payload)?;

            if key_pos + path_nibbles.len() > key_nibbles.len() {
                return Err(ProgramError::TriePathMismatch);
            }
            if key_nibbles[key_pos..key_pos + path_nibbles.len()] != path_nibbles[..] {
                return Err(ProgramError::TriePathMismatch);
            }
            key_pos += path_nibbles.len();

            if is_leaf {
                if key_pos != key_nibbles.len() {
                    return Err(ProgramError::TriePathMismatch);
                }
                if items[1].payload != receipt_envelope {
                    return Err(ProgramError::TrieLeafValueMismatch);
                }
                return Ok(());
            }

            if i + 1 >= proof_nodes_rlp.len() {
                return Err(ProgramError::ProofNodeMismatch);
            }

            let next_node = &proof_nodes_rlp[i + 1];
            if !child_ref_matches(items[1].payload, next_node) {
                return Err(ProgramError::ProofNodeMismatch);
            }
            continue;
        }

        return Err(ProgramError::TrieNodeShapeUnexpected);
    }

    Err(ProgramError::TrieLeafValueMismatch)
}
