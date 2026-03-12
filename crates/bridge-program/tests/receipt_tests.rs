mod helpers;
use bridge_program::receipt::parse_receipt_logs;
use helpers::{build_receipt_with_log, concat, rlp_list, rlp_string};

// ---- helpers ----

fn zero_topic() -> [u8; 32] {
    [0u8; 32]
}

fn zero_address() -> [u8; 20] {
    [0u8; 20]
}

/// Build a receipt with zero logs.
fn empty_receipt() -> Vec<u8> {
    let bloom = [0u8; 256];
    let gas_used_bytes = [0x52u8, 0x08]; // 21000
    let receipt_payload = concat(&[
        rlp_string(&[0x01]),         // status
        rlp_string(&gas_used_bytes), // cumGasUsed
        rlp_string(&bloom),          // logsBloom
        rlp_list(&[]),               // empty logs
    ]);
    rlp_list(&receipt_payload)
}

// ---- legacy receipt (no type prefix) ----

#[test]
fn legacy_receipt_no_logs() {
    let receipt = empty_receipt();
    let logs = parse_receipt_logs(&receipt).unwrap();
    assert_eq!(logs.len(), 0);
}

#[test]
fn legacy_receipt_one_log() {
    let address = [0x11u8; 20];
    let topic0 = [0xaau8; 32];
    let receipt = build_receipt_with_log(address, &[topic0], &[]);
    let logs = parse_receipt_logs(&receipt).unwrap();
    assert_eq!(logs.len(), 1);
    assert_eq!(logs[0].address.as_slice(), &address);
    assert_eq!(logs[0].topics.len(), 1);
    assert_eq!(logs[0].topics[0].as_slice(), &topic0);
    assert_eq!(logs[0].data.len(), 0);
}

#[test]
fn legacy_receipt_log_with_data() {
    let address = [0x22u8; 20];
    let topics = [[0xbbu8; 32], [0xccu8; 32]];
    let data = [0x01u8; 64]; // 2 × 32-byte words
    let receipt = build_receipt_with_log(address, &topics, &data);
    let logs = parse_receipt_logs(&receipt).unwrap();
    assert_eq!(logs.len(), 1);
    assert_eq!(logs[0].topics.len(), 2);
    assert_eq!(logs[0].data, data);
}

// ---- typed receipt (type prefix 0x02) ----

#[test]
fn typed_receipt_no_logs() {
    let mut receipt = vec![0x02u8]; // type prefix
    receipt.extend_from_slice(&empty_receipt());
    let logs = parse_receipt_logs(&receipt).unwrap();
    assert_eq!(logs.len(), 0);
}

#[test]
fn typed_receipt_one_log() {
    let address = [0x33u8; 20];
    let topic = [0xddu8; 32];
    let legacy_part = build_receipt_with_log(address, &[topic], &[]);
    let mut receipt = vec![0x02u8];
    receipt.extend_from_slice(&legacy_part);
    let logs = parse_receipt_logs(&receipt).unwrap();
    assert_eq!(logs.len(), 1);
    assert_eq!(logs[0].address.as_slice(), &address);
}

// ---- error paths ----

#[test]
fn empty_input_is_error() {
    // empty slice: offset >= input.len() → RlpInvalid → ReceiptDecodeFailed
    let result = parse_receipt_logs(&[]);
    assert!(result.is_err());
}

#[test]
fn non_list_root_is_error() {
    // A bare string (0x83 "abc") is not a receipt list
    let data = [0x83u8, b'a', b'b', b'c'];
    let result = parse_receipt_logs(&data);
    assert!(result.is_err());
}

#[test]
fn too_few_fields_is_error() {
    // A list with only 3 items instead of 4
    let three_items =
        concat(&[rlp_string(&[0x01]), rlp_string(&[0x52, 0x08]), rlp_string(&[0u8; 256])]);
    let receipt = rlp_list(&three_items);
    let result = parse_receipt_logs(&receipt);
    assert!(result.is_err());
}
