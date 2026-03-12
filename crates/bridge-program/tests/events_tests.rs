mod helpers;
use alloy_primitives::{keccak256, Address, B256, U256};
use bridge_program::{
    events::{extract_attestation_submitted, validate_deposit_log},
    receipt::Log,
};
use helpers::concat;
use sp1_types::{
    DepositExpectation, FieldAddress, FieldB256, FieldLocation, FieldU256, FieldU64, ProgramError,
};

// ---- helpers ----

fn deposit_topic0() -> B256 {
    keccak256(b"Deposit(address,uint256,address,address,uint256,uint256,uint256,bytes32)")
}

fn attestation_topic0() -> B256 {
    keccak256(b"AttestationSubmitted(address,uint256,bytes32,uint256,bytes32,uint256)")
}

/// Pad an address to 32 bytes (left-padded with zeros).
fn addr_to_b256(addr: [u8; 20]) -> [u8; 32] {
    let mut b = [0u8; 32];
    b[12..].copy_from_slice(&addr);
    b
}

/// Build a 5-word data payload: [amount, to, sourceChain, destChain, depositIndex].
fn build_deposit_data(amount: U256, to: Address, source: u64, dest: u64, index: u64) -> Vec<u8> {
    let mut data = Vec::with_capacity(160);
    data.extend_from_slice(&amount.to_be_bytes::<32>());

    let mut to_word = [0u8; 32];
    to_word[12..].copy_from_slice(to.as_slice());
    data.extend_from_slice(&to_word);

    let mut src_word = [0u8; 32];
    src_word[24..].copy_from_slice(&source.to_be_bytes());
    data.extend_from_slice(&src_word);

    let mut dst_word = [0u8; 32];
    dst_word[24..].copy_from_slice(&dest.to_be_bytes());
    data.extend_from_slice(&dst_word);

    let mut idx_word = [0u8; 32];
    idx_word[24..].copy_from_slice(&index.to_be_bytes());
    data.extend_from_slice(&idx_word);

    data
}

fn make_deposit_log(
    bridge: Address,
    who: Address,
    token: Address,
    deposit_root: B256,
    amount: U256,
    to: Address,
    source: u64,
    dest: u64,
    index: u64,
) -> Log {
    Log {
        address: bridge,
        topics: vec![
            deposit_topic0(),
            B256::from_slice(&addr_to_b256(*who.as_ref())),
            B256::from_slice(&addr_to_b256(*token.as_ref())),
            deposit_root,
        ],
        data: build_deposit_data(amount, to, source, dest, index),
    }
}

// ---- validate_deposit_log ----

#[test]
fn valid_deposit_log_returns_root_and_index() {
    let bridge = Address::from([0x01u8; 20]);
    let who = Address::from([0x02u8; 20]);
    let token = Address::from([0x03u8; 20]);
    let deposit_root = B256::from([0xaau8; 32]);
    let amount = U256::from(1_000_000u64);
    let to = Address::from([0x04u8; 20]);
    let index = 7u64;

    let log = make_deposit_log(bridge, who, token, deposit_root, amount, to, 1, 8453, index);

    let expected = DepositExpectation {
        bridge,
        topic0: deposit_topic0(),
        deposit_root: FieldB256 { value: deposit_root, location: FieldLocation::Topic(3) },
        deposit_index: FieldU64 { value: index, location: FieldLocation::DataWord(4) },
        amount: FieldU256 { value: amount, location: FieldLocation::DataWord(0) },
        to: FieldAddress { value: to, location: FieldLocation::DataWord(1) },
    };

    let (root_out, index_out) = validate_deposit_log(&[log], &expected).unwrap();
    assert_eq!(root_out, deposit_root);
    assert_eq!(index_out, index);
}

#[test]
fn wrong_topic0_skips_log() {
    let bridge = Address::from([0x01u8; 20]);
    let deposit_root = B256::from([0xaau8; 32]);
    let amount = U256::from(100u64);
    let to = Address::from([0x04u8; 20]);

    let mut log = make_deposit_log(
        bridge,
        Address::ZERO,
        Address::ZERO,
        deposit_root,
        amount,
        to,
        1,
        8453,
        0,
    );
    log.topics[0] = B256::from([0xffu8; 32]); // wrong event sig

    let expected = DepositExpectation {
        bridge,
        topic0: deposit_topic0(),
        deposit_root: FieldB256 { value: deposit_root, location: FieldLocation::Topic(3) },
        deposit_index: FieldU64 { value: 0, location: FieldLocation::DataWord(4) },
        amount: FieldU256 { value: amount, location: FieldLocation::DataWord(0) },
        to: FieldAddress { value: to, location: FieldLocation::DataWord(1) },
    };

    assert_eq!(validate_deposit_log(&[log], &expected), Err(ProgramError::DepositLogNotFound));
}

#[test]
fn wrong_bridge_address_skips_log() {
    let bridge = Address::from([0x01u8; 20]);
    let wrong_bridge = Address::from([0x99u8; 20]);
    let deposit_root = B256::from([0xaau8; 32]);
    let amount = U256::from(100u64);
    let to = Address::from([0x04u8; 20]);

    let log = make_deposit_log(
        wrong_bridge,
        Address::ZERO,
        Address::ZERO,
        deposit_root,
        amount,
        to,
        1,
        8453,
        0,
    );

    let expected = DepositExpectation {
        bridge, // expects a different bridge
        topic0: deposit_topic0(),
        deposit_root: FieldB256 { value: deposit_root, location: FieldLocation::Topic(3) },
        deposit_index: FieldU64 { value: 0, location: FieldLocation::DataWord(4) },
        amount: FieldU256 { value: amount, location: FieldLocation::DataWord(0) },
        to: FieldAddress { value: to, location: FieldLocation::DataWord(1) },
    };

    assert_eq!(validate_deposit_log(&[log], &expected), Err(ProgramError::DepositLogNotFound));
}

#[test]
fn mismatched_deposit_root_is_error() {
    let bridge = Address::from([0x01u8; 20]);
    let deposit_root = B256::from([0xaau8; 32]);
    let wrong_root = B256::from([0xbbu8; 32]);
    let amount = U256::from(100u64);
    let to = Address::from([0x04u8; 20]);

    let log = make_deposit_log(
        bridge,
        Address::ZERO,
        Address::ZERO,
        deposit_root,
        amount,
        to,
        1,
        8453,
        0,
    );

    let expected = DepositExpectation {
        bridge,
        topic0: deposit_topic0(),
        deposit_root: FieldB256 { value: wrong_root, location: FieldLocation::Topic(3) },
        deposit_index: FieldU64 { value: 0, location: FieldLocation::DataWord(4) },
        amount: FieldU256 { value: amount, location: FieldLocation::DataWord(0) },
        to: FieldAddress { value: to, location: FieldLocation::DataWord(1) },
    };

    assert_eq!(validate_deposit_log(&[log], &expected), Err(ProgramError::DepositFieldMismatch));
}

// ---- extract_attestation_submitted ----

fn make_attestation_log(
    validator_manager: Address,
    validator: Address,
    chain_id: u64,
    bridge_root: B256,
    block_number: u64,
    state_root: B256,
    timestamp: u64,
) -> Log {
    let mut chain_id_word = [0u8; 32];
    chain_id_word[24..].copy_from_slice(&chain_id.to_be_bytes());

    let mut block_number_data = [0u8; 32];
    block_number_data[24..].copy_from_slice(&block_number.to_be_bytes());
    let mut timestamp_data = [0u8; 32];
    timestamp_data[24..].copy_from_slice(&timestamp.to_be_bytes());

    let data = concat(&[
        block_number_data.to_vec(),
        state_root.as_slice().to_vec(),
        timestamp_data.to_vec(),
    ]);

    Log {
        address: validator_manager,
        topics: vec![
            attestation_topic0(),
            B256::from_slice(&addr_to_b256(*validator.as_ref())),
            B256::from(chain_id_word),
            bridge_root,
        ],
        data,
    }
}

#[test]
fn valid_attestation_log() {
    let vm = Address::from([0x10u8; 20]);
    let validator = Address::from([0x20u8; 20]);
    let chain_id = 1u64;
    let bridge_root = B256::from([0x99u8; 32]);
    let block_number = 42u64;
    let state_root = B256::from([0x55u8; 32]);
    let timestamp = 1_700_000_000u64;

    let log = make_attestation_log(
        vm,
        validator,
        chain_id,
        bridge_root,
        block_number,
        state_root,
        timestamp,
    );
    let (v, c, r, b, s, t) = extract_attestation_submitted(&[log], vm).unwrap();
    assert_eq!(v, validator);
    assert_eq!(c, chain_id);
    assert_eq!(r, bridge_root);
    assert_eq!(b, block_number);
    assert_eq!(s, state_root);
    assert_eq!(t, timestamp);
}

#[test]
fn attestation_wrong_address_is_error() {
    let vm = Address::from([0x10u8; 20]);
    let wrong_vm = Address::from([0x11u8; 20]);
    let log = make_attestation_log(wrong_vm, Address::ZERO, 1, B256::ZERO, 1, B256::ZERO, 1);
    assert_eq!(
        extract_attestation_submitted(&[log], vm),
        Err(ProgramError::AttestationLogNotFound)
    );
}

#[test]
fn attestation_wrong_topic0_is_error() {
    let vm = Address::from([0x10u8; 20]);
    let mut log = make_attestation_log(vm, Address::ZERO, 1, B256::ZERO, 1, B256::ZERO, 1);
    log.topics[0] = B256::from([0xffu8; 32]);
    assert_eq!(
        extract_attestation_submitted(&[log], vm),
        Err(ProgramError::AttestationLogNotFound)
    );
}
