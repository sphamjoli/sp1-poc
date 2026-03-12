extern crate alloc;

use crate::rlp::{list_items, parse_item};
use alloc::vec::Vec;
use alloy_primitives::{Address, B256};
use sp1_types::{ProgramError, ProgramResult};

#[derive(Clone, Debug)]
pub struct Log {
    pub address: Address,
    pub topics: Vec<B256>,
    pub data: Vec<u8>,
}

/// Parse receipt envelope and return logs.
///
/// Envelope rules:
/// - typed: <type_byte> || rlp(list)
/// - legacy: rlp(list)
pub fn parse_receipt_logs(receipt_envelope: &[u8]) -> ProgramResult<Vec<Log>> {
    let payload = if !receipt_envelope.is_empty() && receipt_envelope[0] <= 0x7f {
        &receipt_envelope[1..]
    } else {
        receipt_envelope
    };

    let (root, next) = parse_item(payload, 0).map_err(|_| ProgramError::ReceiptDecodeFailed)?;
    if next != payload.len() {
        return Err(ProgramError::RlpTrailingBytes);
    }
    if !root.is_list {
        return Err(ProgramError::ReceiptDecodeFailed);
    }

    let fields = list_items(root.payload).map_err(|_| ProgramError::ReceiptDecodeFailed)?;
    if fields.len() < 4 {
        return Err(ProgramError::ReceiptDecodeFailed);
    }

    let logs_item = &fields[3];
    if !logs_item.is_list {
        return Err(ProgramError::ReceiptDecodeFailed);
    }

    let mut out = Vec::new();
    for log_item in list_items(logs_item.payload).map_err(|_| ProgramError::ReceiptDecodeFailed)? {
        if !log_item.is_list {
            return Err(ProgramError::ReceiptDecodeFailed);
        }
        let parts = list_items(log_item.payload).map_err(|_| ProgramError::ReceiptDecodeFailed)?;
        if parts.len() != 3 {
            return Err(ProgramError::ReceiptDecodeFailed);
        }

        if parts[0].payload.len() != 20 {
            return Err(ProgramError::ReceiptDecodeFailed);
        }
        let address = Address::from_slice(parts[0].payload);

        if !parts[1].is_list {
            return Err(ProgramError::ReceiptDecodeFailed);
        }
        let mut topics = Vec::new();
        for t in list_items(parts[1].payload).map_err(|_| ProgramError::ReceiptDecodeFailed)? {
            if t.payload.len() != 32 {
                return Err(ProgramError::ReceiptDecodeFailed);
            }
            topics.push(B256::from_slice(t.payload));
        }

        let data = parts[2].payload.to_vec();
        out.push(Log { address, topics, data });
    }

    Ok(out)
}
