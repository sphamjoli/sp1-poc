mod helpers;
use alloy_primitives::{keccak256, Address, Bytes, B256, U256};
use bridge_program::comparer::build_public_values;
use helpers::{build_receipt_with_log, build_single_leaf_mpt};
use sp1_types::{
    AttestationWitness, BatchInput, DepositExpectation, FieldAddress, FieldB256, FieldLocation,
    FieldU256, FieldU64, ProgramError, ReceiptWitness, ZkvmInput,
};

// ---- helpers ----

fn deposit_topic0() -> B256 {
    keccak256(b"Deposit(address,uint256,address,address,uint256,uint256,uint256,bytes32)")
}

fn addr_to_b256(addr: [u8; 20]) -> [u8; 32] {
    let mut b = [0u8; 32];
    b[12..].copy_from_slice(&addr);
    b
}

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

/// Build a valid ZkvmInput for a single deposit, no attestations.
fn make_valid_single_deposit_input() -> ZkvmInput {
    let bridge = Address::from([0x01u8; 20]);
    let who = [0x02u8; 20];
    let token = [0x03u8; 20];
    let deposit_root = B256::from([0xaau8; 32]);
    let amount = U256::from(1_000u64);
    let to = Address::from([0x04u8; 20]);
    let deposit_index = 0u64;

    let topic0 = deposit_topic0();
    let topics: [[u8; 32]; 4] =
        [*topic0.as_ref(), addr_to_b256(who), addr_to_b256(token), *deposit_root.as_ref()];
    let log_data = build_deposit_data(amount, to, 1, 8453, deposit_index);

    let receipt_bytes = build_receipt_with_log([0x01u8; 20], &topics, &log_data);
    let (receipts_root, proof_nodes) = build_single_leaf_mpt(&receipt_bytes);

    let expected = DepositExpectation {
        bridge,
        topic0,
        deposit_root: FieldB256 { value: deposit_root, location: FieldLocation::Topic(3) },
        deposit_index: FieldU64 { value: deposit_index, location: FieldLocation::DataWord(4) },
        amount: FieldU256 { value: amount, location: FieldLocation::DataWord(0) },
        to: FieldAddress { value: to, location: FieldLocation::DataWord(1) },
    };

    ZkvmInput {
        attested_chain_id: 1,
        deposit_batch: BatchInput {
            chain_id: 1,
            block_number: 100,
            receipts_root,
            header_hash: None,
            receipts: vec![ReceiptWitness {
                tx_index: 0,
                receipt_envelope: Bytes::from(receipt_bytes),
                proof_nodes_rlp: proof_nodes.into_iter().map(Bytes::from).collect(),
                expected,
            }],
        },
        attestations: vec![],
        slash_amount: U256::from(100u64),
    }
}

// ---- happy path ----

#[test]
fn valid_single_deposit_no_attestations() {
    let input = make_valid_single_deposit_input();
    let result = build_public_values(&input);
    assert!(result.is_ok(), "expected Ok, got {:?}", result.err());
    // public values is ABI-encoded; just verify it's non-empty
    assert!(!result.unwrap().is_empty());
}

// ---- error paths ----

#[test]
fn empty_deposit_batch_returns_error() {
    let input = ZkvmInput {
        attested_chain_id: 1,
        deposit_batch: BatchInput {
            chain_id: 1,
            block_number: 100,
            receipts_root: B256::ZERO,
            header_hash: None,
            receipts: vec![],
        },
        attestations: vec![],
        slash_amount: U256::ZERO,
    };
    assert_eq!(build_public_values(&input), Err(ProgramError::EmptyDeposits));
}

#[test]
fn receipt_with_empty_proof_returns_error() {
    let receipt_bytes = vec![0x01u8];
    let input = ZkvmInput {
        attested_chain_id: 1,
        deposit_batch: BatchInput {
            chain_id: 1,
            block_number: 100,
            receipts_root: B256::ZERO,
            header_hash: None,
            receipts: vec![ReceiptWitness {
                tx_index: 0,
                receipt_envelope: Bytes::from(receipt_bytes),
                proof_nodes_rlp: vec![],
                expected: DepositExpectation {
                    bridge: Address::ZERO,
                    topic0: B256::ZERO,
                    deposit_root: FieldB256 {
                        value: B256::ZERO,
                        location: FieldLocation::Topic(3),
                    },
                    deposit_index: FieldU64 { value: 0, location: FieldLocation::DataWord(4) },
                    amount: FieldU256 { value: U256::ZERO, location: FieldLocation::DataWord(0) },
                    to: FieldAddress { value: Address::ZERO, location: FieldLocation::DataWord(1) },
                },
            }],
        },
        attestations: vec![],
        slash_amount: U256::ZERO,
    };
    assert_eq!(build_public_values(&input), Err(ProgramError::ProofIsEmpty));
}

#[test]
fn batch_shape_mismatch_for_mixed_attestation_chain_ids() {
    let mut input = make_valid_single_deposit_input();

    let dummy_attestation = |chain_id: u64| AttestationWitness {
        receipts_root: B256::ZERO,
        validator_manager: Address::ZERO,
        validator: Address::ZERO,
        source_chain_id: chain_id,
        bridge_root: B256::ZERO,
        block_number: 100,
        state_root: B256::ZERO,
        timestamp: 0,
        tx_index: 0,
        receipt_envelope: Bytes::from(vec![0x01u8]),
        proof_nodes_rlp: vec![],
    };

    input.attestations = vec![dummy_attestation(1), dummy_attestation(8453)];
    assert_eq!(build_public_values(&input), Err(ProgramError::BatchShapeMismatch));
}
