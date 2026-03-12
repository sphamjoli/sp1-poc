#![no_std]
extern crate alloc;

use alloc::vec::Vec;
use alloy_primitives::{Address, Bytes, B256, U256};
/// Deterministic error set for the zkVM program.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProgramError {
    RlpInvalid,
    RlpTrailingBytes,
    ProofIsEmpty,
    ProofRootMismatch,
    ProofNodeMismatch,
    TriePathMismatch,
    TrieNodeShapeUnexpected,
    TrieLeafValueMismatch,
    ReceiptDecodeFailed,
    DepositLogNotFound,
    DepositFieldMismatch,
    AttestationLogNotFound,
    AttestationFieldMismatch,
    BatchShapeMismatch,
    EmptyDeposits,
}

pub type ProgramResult<T> = core::result::Result<T, ProgramError>;

#[derive(Clone, serde::Serialize, serde::Deserialize, Debug)]
pub enum FieldLocation {
    Topic(u8),
    DataWord(u8),
}

#[derive(Clone, serde::Serialize, serde::Deserialize, Debug)]
pub struct FieldB256 {
    pub value: B256,
    pub location: FieldLocation,
}

#[derive(Clone, serde::Serialize, serde::Deserialize, Debug)]
pub struct FieldU64 {
    pub value: u64,
    pub location: FieldLocation,
}

#[derive(Clone, serde::Serialize, serde::Deserialize, Debug)]
pub struct FieldU256 {
    pub value: U256,
    pub location: FieldLocation,
}

#[derive(Clone, serde::Serialize, serde::Deserialize, Debug)]
pub struct FieldAddress {
    pub value: Address,
    pub location: FieldLocation,
}

/// Deposit log constraints enforced by the zkVM program.
#[derive(Clone, serde::Serialize, serde::Deserialize, Debug)]
pub struct DepositExpectation {
    pub bridge: Address,
    pub topic0: B256,
    pub deposit_root: FieldB256,
    pub deposit_index: FieldU64,
    pub amount: FieldU256,
    pub to: FieldAddress,
}

/// Receipt witness for a single transaction in the receipts trie.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct ReceiptWitness {
    pub tx_index: u64,
    pub receipt_envelope: Bytes,
    pub proof_nodes_rlp: Vec<Bytes>,
    pub expected: DepositExpectation,
}

/// Deposits batch for a single finalized block.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct BatchInput {
    pub chain_id: u64,
    pub block_number: u64,
    pub receipts_root: B256,
    pub header_hash: Option<B256>,
    pub receipts: Vec<ReceiptWitness>,
}

/// Attestation witness proves AttestationSubmitted exists on-chain.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct AttestationWitness {
    /// receipts_root of the block containing the submitAttestation tx.
    pub receipts_root: B256,

    /// ValidatorManager address (log.address must match).
    pub validator_manager: Address,

    /// Expected validator (indexed topic1).
    pub validator: Address,

    /// Expected source chain identifier emitted in AttestationSubmitted (indexed topic2).
    pub source_chain_id: u64,

    /// Expected bridgeRoot emitted (indexed topic3).
    pub bridge_root: B256,

    /// Expected blockNumber emitted in event data word 0.
    pub block_number: u64,

    /// Expected stateRoot emitted in event data word 1.
    pub state_root: B256,

    /// Expected timestamp emitted in event data word 2.
    pub timestamp: u64,

    /// Receipt trie inclusion proof.
    pub tx_index: u64,
    pub receipt_envelope: Bytes,
    pub proof_nodes_rlp: Vec<Bytes>,
}

/// zkVM input.
///
/// - `attested_chain_id` is the source chain id proven by the batch.
/// - `deposit_batch` defines the canonical `validBridgeRoot`.
/// - `attestations` are receipts on the chain where ValidatorManager emitted AttestationSubmitted.
/// - `slash_amount` is used to populate SlashParams.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ZkvmInput {
    pub attested_chain_id: u64,
    pub deposit_batch: BatchInput,
    pub attestations: Vec<AttestationWitness>,
    pub slash_amount: U256,
}
