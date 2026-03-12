extern crate alloc;
use alloy_primitives::{keccak256, Address, B256, U256};

use crate::receipt::Log;
use sp1_types::{DepositExpectation, FieldLocation, ProgramError, ProgramResult};

fn word_at(data: &[u8], index: u8) -> ProgramResult<&[u8]> {
    let i = index as usize;
    let start = 32 * i;
    let end = start + 32;
    if end > data.len() {
        return Err(ProgramError::DepositFieldMismatch);
    }
    Ok(&data[start..end])
}

fn u256_from_word(word: &[u8]) -> U256 {
    U256::from_be_slice(word)
}

fn address_from_word(word: &[u8]) -> Address {
    Address::from_slice(&word[12..32])
}

fn address_from_topic(topic: B256) -> Address {
    Address::from_slice(&topic.as_slice()[12..32])
}

fn read_b256(loc: &FieldLocation, topics: &[B256], data: &[u8]) -> ProgramResult<B256> {
    match *loc {
        FieldLocation::Topic(i) => {
            topics.get(i as usize).copied().ok_or(ProgramError::DepositFieldMismatch)
        }
        FieldLocation::DataWord(i) => Ok(B256::from_slice(word_at(data, i)?)),
    }
}

fn read_u64(loc: &FieldLocation, topics: &[B256], data: &[u8]) -> ProgramResult<u64> {
    match *loc {
        FieldLocation::Topic(i) => {
            let t = topics.get(i as usize).ok_or(ProgramError::DepositFieldMismatch)?;
            Ok(U256::from_be_slice(t.as_slice()).to::<u64>())
        }
        FieldLocation::DataWord(i) => Ok(u256_from_word(word_at(data, i)?).to::<u64>()),
    }
}

fn read_u256(loc: &FieldLocation, topics: &[B256], data: &[u8]) -> ProgramResult<U256> {
    match *loc {
        FieldLocation::Topic(i) => {
            let t = topics.get(i as usize).ok_or(ProgramError::DepositFieldMismatch)?;
            Ok(U256::from_be_slice(t.as_slice()))
        }
        FieldLocation::DataWord(i) => Ok(u256_from_word(word_at(data, i)?)),
    }
}

fn read_address(loc: &FieldLocation, topics: &[B256], data: &[u8]) -> ProgramResult<Address> {
    match *loc {
        FieldLocation::Topic(i) => topics
            .get(i as usize)
            .copied()
            .map(address_from_topic)
            .ok_or(ProgramError::DepositFieldMismatch),
        FieldLocation::DataWord(i) => Ok(address_from_word(word_at(data, i)?)),
    }
}

/// Validate Deposit log against `DepositExpectation`.
/// Returns the (deposit_root, deposit_index) extracted from the matched log.
pub fn validate_deposit_log(
    logs: &[Log],
    expected: &DepositExpectation,
) -> ProgramResult<(B256, u64)> {
    for log in logs {
        if log.address != expected.bridge {
            continue;
        }
        if log.topics.is_empty() || log.topics[0] != expected.topic0 {
            continue;
        }

        let deposit_root = read_b256(&expected.deposit_root.location, &log.topics, &log.data)?;
        let deposit_index = read_u64(&expected.deposit_index.location, &log.topics, &log.data)?;
        let amount = read_u256(&expected.amount.location, &log.topics, &log.data)?;
        let to = read_address(&expected.to.location, &log.topics, &log.data)?;

        if deposit_root != expected.deposit_root.value {
            return Err(ProgramError::DepositFieldMismatch);
        }
        if deposit_index != expected.deposit_index.value {
            return Err(ProgramError::DepositFieldMismatch);
        }
        if amount != expected.amount.value {
            return Err(ProgramError::DepositFieldMismatch);
        }
        if to != expected.to.value {
            return Err(ProgramError::DepositFieldMismatch);
        }

        return Ok((deposit_root, deposit_index));
    }

    Err(ProgramError::DepositLogNotFound)
}

/// Extract AttestationSubmitted(validator, sourceChainId, bridgeRoot, blockNumber, stateRoot, timestamp).
///
/// Solidity event:
/// `AttestationSubmitted(address indexed validator, uint256 indexed sourceChainId, bytes32 indexed bridgeRoot, uint256 blockNumber, bytes32 stateRoot, uint256 timestamp)`
pub fn extract_attestation_submitted(
    logs: &[Log],
    validator_manager: Address,
) -> ProgramResult<(Address, u64, B256, u64, B256, u64)> {
    let sig = keccak256(b"AttestationSubmitted(address,uint256,bytes32,uint256,bytes32,uint256)");

    for log in logs {
        if log.address != validator_manager {
            continue;
        }
        if log.topics.len() != 4 {
            continue;
        }
        if log.topics[0] != sig {
            continue;
        }

        let validator = address_from_topic(log.topics[1]);
        let chain_id = U256::from_be_slice(log.topics[2].as_slice()).to::<u64>();
        let bridge_root = log.topics[3];

        if log.data.len() != 96 {
            return Err(ProgramError::AttestationFieldMismatch);
        }
        let block_number = U256::from_be_slice(&log.data[0..32]).to::<u64>();
        let state_root = B256::from_slice(&log.data[32..64]);
        let timestamp = U256::from_be_slice(&log.data[64..96]).to::<u64>();

        return Ok((validator, chain_id, bridge_root, block_number, state_root, timestamp));
    }

    Err(ProgramError::AttestationLogNotFound)
}
