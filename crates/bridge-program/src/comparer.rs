extern crate alloc;

use alloc::{collections::BTreeMap, vec::Vec};
use alloy_primitives::{Address, B256, U256};

use crate::{abi, events, mpt, receipt};
use sp1_types::{AttestationWitness, BatchInput, ZkvmInput};
use sp1_types::{ProgramError, ProgramResult};

pub fn build_public_values(input: &ZkvmInput) -> ProgramResult<Vec<u8>> {
    let (valid_bridge_root, _max_deposit_index) =
        compute_valid_root_from_deposits(&input.deposit_batch)?;

    let attestation_records = verify_attestations(&input.attestations)?;

    let equivocators =
        compute_equivocators(&attestation_records, valid_bridge_root, input.slash_amount);

    let attestations_out: Vec<crate::abi::BridgeAttestation> = attestation_records
        .into_iter()
        .map(|record| crate::abi::BridgeAttestation {
            blockNumber: U256::from(record.block_number),
            bridgeRoot: record.bridge_root.0.into(),
            stateRoot: record.state_root.0.into(),
            sourceChainId: U256::from(record.source_chain_id),
            timestamp: U256::from(record.timestamp),
            validator: record.validator,
            certificate: Vec::new().into(),
            signature: [U256::ZERO, U256::ZERO],
        })
        .collect();

    Ok(abi::encode_public_values(
        input.attested_chain_id,
        valid_bridge_root,
        attestations_out,
        equivocators,
    ))
}

/// Result of an attestation verification within the zkVM.
#[derive(Clone, Copy)]
struct AttestationRecord {
    validator: Address,
    source_chain_id: u64,
    block_number: u64,
    bridge_root: B256,
    state_root: B256,
    timestamp: u64,
}

fn compute_valid_root_from_deposits(batch: &BatchInput) -> ProgramResult<(B256, u64)> {
    if batch.receipts.is_empty() {
        return Err(ProgramError::EmptyDeposits);
    }

    let mut best_root = B256::ZERO;
    let mut best_index: u64 = 0;
    let mut seen_any = false;

    for w in &batch.receipts {
        let receipt_bytes: Vec<u8> = w.receipt_envelope.to_vec();
        let proof_nodes: Vec<Vec<u8>> = w.proof_nodes_rlp.iter().map(|b| b.to_vec()).collect();

        mpt::verify_receipt_inclusion(
            batch.receipts_root,
            w.tx_index,
            &receipt_bytes,
            &proof_nodes,
        )?;

        let logs = receipt::parse_receipt_logs(&receipt_bytes)?;
        let (root, index) = events::validate_deposit_log(&logs, &w.expected)?;

        if !seen_any || index > best_index {
            best_index = index;
            best_root = root;
            seen_any = true;
        }
    }

    if !seen_any {
        return Err(ProgramError::DepositLogNotFound);
    }

    Ok((best_root, best_index))
}

fn verify_attestations(
    attestations: &[AttestationWitness],
) -> ProgramResult<Vec<AttestationRecord>> {
    if attestations.is_empty() {
        return Ok(Vec::new());
    }

    let first_chain_id = attestations[0].source_chain_id;
    let first_block_number = attestations[0].block_number;
    for a in attestations {
        if a.source_chain_id != first_chain_id || a.block_number != first_block_number {
            return Err(ProgramError::BatchShapeMismatch);
        }
    }

    let mut out = Vec::with_capacity(attestations.len());
    for a in attestations {
        let receipt_bytes: Vec<u8> = a.receipt_envelope.to_vec();
        let proof_nodes: Vec<Vec<u8>> = a.proof_nodes_rlp.iter().map(|b| b.to_vec()).collect();

        mpt::verify_receipt_inclusion(a.receipts_root, a.tx_index, &receipt_bytes, &proof_nodes)?;

        let logs = receipt::parse_receipt_logs(&receipt_bytes)?;
        let (validator, source_chain_id, bridge_root, block_number, state_root, timestamp) =
            events::extract_attestation_submitted(&logs, a.validator_manager)?;

        if validator != a.validator
            || source_chain_id != a.source_chain_id
            || bridge_root != a.bridge_root
            || block_number != a.block_number
            || state_root != a.state_root
            || timestamp != a.timestamp
        {
            return Err(ProgramError::AttestationFieldMismatch);
        }

        out.push(AttestationRecord {
            validator,
            source_chain_id,
            block_number,
            bridge_root,
            state_root,
            timestamp,
        });
    }

    Ok(out)
}

fn compute_equivocators(
    records: &[AttestationRecord],
    valid_bridge_root: B256,
    slash_amount: U256,
) -> Vec<crate::abi::SlashParams> {
    let mut map: BTreeMap<Address, (B256, U256)> = BTreeMap::new();

    for record in records {
        let entry = map.entry(record.validator).or_insert((record.bridge_root, U256::from(0)));

        if record.bridge_root != valid_bridge_root {
            entry.1 = entry.1.saturating_add(slash_amount);
        }

        if entry.0 != record.bridge_root {
            entry.1 = entry.1.saturating_add(slash_amount);
        }
    }

    map.into_iter()
        .filter(|(_, (_, amount))| *amount > U256::ZERO)
        .map(|(validator, (_, amount))| crate::abi::SlashParams { validator, slashAmount: amount })
        .collect()
}
