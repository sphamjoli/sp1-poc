#[path = "common/rlp.rs"]
mod rlp_helpers;
use alloy_primitives::{keccak256, Address, Bytes, B256, U256};
use bridge_program::comparer::build_public_values;
use rlp_helpers as helpers;
#[path = "common/mpt.rs"]
mod mpt_helpers;
#[path = "common/receipt.rs"]
mod receipt_helpers;
use mpt_helpers::build_single_leaf_mpt;
use receipt_helpers::build_receipt_with_log;
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

#[test]
fn rejects_public_chain_id_unrelated_to_deposit_batch() {
    let mut input = make_valid_single_deposit_input();
    input.attested_chain_id = 8453;
    assert_eq!(build_public_values(&input), Err(ProgramError::BatchShapeMismatch));
}

#[test]
fn rejects_attestations_for_a_different_deposit_block_or_chain() {
    for (chain_id, block_number) in [(8453, 100), (1, 101)] {
        let mut input = make_valid_single_deposit_input();
        input.attestations.push(AttestationWitness {
            receipts_root: B256::ZERO,
            validator_manager: Address::ZERO,
            validator: Address::ZERO,
            source_chain_id: chain_id,
            bridge_root: B256::ZERO,
            block_number,
            state_root: B256::ZERO,
            timestamp: 0,
            tx_index: 0,
            receipt_envelope: Bytes::new(),
            proof_nodes_rlp: vec![],
        });
        assert_eq!(build_public_values(&input), Err(ProgramError::BatchShapeMismatch));
    }
}

#[test]
fn rejects_duplicate_attestation_receipts_before_slashing() {
    let mut input = make_valid_single_deposit_input();
    let attestation = AttestationWitness {
        receipts_root: B256::ZERO,
        validator_manager: Address::ZERO,
        validator: Address::ZERO,
        source_chain_id: 1,
        bridge_root: B256::ZERO,
        block_number: 100,
        state_root: B256::ZERO,
        timestamp: 0,
        tx_index: 0,
        receipt_envelope: Bytes::new(),
        proof_nodes_rlp: vec![],
    };
    input.attestations = vec![attestation.clone(), attestation];
    assert_eq!(build_public_values(&input), Err(ProgramError::BatchShapeMismatch));
}

fn attestation_witness(
    validator: Address,
    bridge_root: B256,
    state_root: B256,
) -> AttestationWitness {
    let topics = [
        *keccak256(b"AttestationSubmitted(address,uint256,bytes32,uint256,bytes32,uint256)")
            .as_ref(),
        addr_to_b256(validator.into_array()),
        U256::from(1).to_be_bytes::<32>(),
        *bridge_root.as_ref(),
    ];
    let data = helpers::concat(&[
        U256::from(100).to_be_bytes::<32>().to_vec(),
        state_root.to_vec(),
        U256::from(10).to_be_bytes::<32>().to_vec(),
    ]);
    let receipt = build_receipt_with_log([0x11; 20], &topics, &data);
    let (receipts_root, proof_nodes) = build_single_leaf_mpt(&receipt);
    AttestationWitness {
        receipts_root,
        validator_manager: Address::from([0x11; 20]),
        validator,
        source_chain_id: 1,
        bridge_root,
        block_number: 100,
        state_root,
        timestamp: 10,
        tx_index: 0,
        receipt_envelope: receipt.into(),
        proof_nodes_rlp: proof_nodes.into_iter().map(Bytes::from).collect(),
    }
}

proptest::proptest! {
    #[test]
    fn public_values_separate_invalid_roots_from_finalisation(
        invalid_root in proptest::prelude::any::<[u8; 32]>(),
    ) {
        use alloy_sol_types::SolValue;
        use bridge_program::abi::VerificationPublicValues;
        let valid_root = B256::from([0xaa; 32]);
        proptest::prop_assume!(invalid_root != valid_root.0);
        let honest = Address::from([0x22; 20]);
        let dishonest = Address::from([0x33; 20]);
        let mut input = make_valid_single_deposit_input();
        input.attestations = vec![
            attestation_witness(honest, valid_root, B256::from([0x55; 32])),
            attestation_witness(dishonest, B256::from(invalid_root), B256::from([0x55; 32])),
        ];
        let bytes = build_public_values(&input).unwrap();
        let public_values = VerificationPublicValues::abi_decode(&bytes).unwrap();
        proptest::prop_assert_eq!(public_values.attestations.len(), 1);
        proptest::prop_assert_eq!(public_values.attestations[0].validator, honest);
        proptest::prop_assert_eq!(public_values.attestations[0].bridgeRoot, valid_root);
        proptest::prop_assert_eq!(public_values.equivocators.len(), 1);
        proptest::prop_assert_eq!(public_values.equivocators[0].validator, dishonest);
        proptest::prop_assert_eq!(public_values.equivocators[0].slashAmount, input.slash_amount);
    }
}

proptest::proptest! {
    #[test]
    fn inconsistent_honest_state_roots_are_rejected(state_root in proptest::prelude::any::<[u8; 32]>()) {
        let first_state = B256::from([0x55; 32]);
        proptest::prop_assume!(state_root != first_state.0);
        let mut input = make_valid_single_deposit_input();
        let valid_root = B256::from([0xaa; 32]);
        input.attestations = vec![
            attestation_witness(Address::from([0x22; 20]), valid_root, first_state),
            attestation_witness(Address::from([0x33; 20]), valid_root, B256::from(state_root)),
        ];
        proptest::prop_assert_eq!(build_public_values(&input), Err(ProgramError::BatchShapeMismatch));
    }
}

#[test]
fn all_bad_finalisation_matches_cross_language_golden_vector() {
    let mut input = make_valid_single_deposit_input();
    input.slash_amount = U256::from(1_000_000_000_000_000_000u64);
    input.attestations = vec![attestation_witness(
        Address::from([0x11; 20]),
        B256::from([0xbb; 32]),
        B256::from([0x55; 32]),
    )];
    let expected = alloy_primitives::hex::decode(
        include_str!("../../../contracts/test/fixtures/all-bad-finalisation.hex").trim(),
    )
    .unwrap();
    assert_eq!(build_public_values(&input).unwrap(), expected);
}
