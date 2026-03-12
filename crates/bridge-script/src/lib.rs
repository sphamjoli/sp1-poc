use alloy::{
    primitives::{keccak256, Address, B256, U256},
    rpc::types::TransactionReceipt,
};
use eyre::{bail, eyre, Result};
use sp1_sdk::{CpuProver, ProverClient};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DepositEventRecord {
    pub deposit_root: B256,
    pub deposit_index: u64,
    pub amount: U256,
    pub recipient: Address,
    pub source_chain_id: u64,
    pub destination_chain_id: u64,
}

pub fn deposit_event_signature() -> B256 {
    keccak256(b"Deposit(address,uint256,address,address,uint256,uint256,uint256,bytes32)")
}

pub fn parse_deposit_event(receipt: &TransactionReceipt) -> Result<DepositEventRecord> {
    let log = receipt
        .inner
        .logs()
        .iter()
        .find(|candidate| candidate.topics().first() == Some(&deposit_event_signature()))
        .ok_or_else(|| eyre!("deposit event not found in receipt {}", receipt.transaction_hash))?;

    let deposit_root =
        log.topics().get(3).copied().ok_or_else(|| eyre!("deposit event missing indexed root"))?;
    let data = log.data().data.as_ref();
    if data.len() < 160 {
        bail!("deposit event data is too short: {}", data.len());
    }

    let amount = U256::from_be_bytes(slice_to_32_bytes(&data[0..32])?);
    let recipient = Address::from_slice(&data[44..64]);
    let source_chain_id = u64::try_from(U256::from_be_bytes(slice_to_32_bytes(&data[64..96])?))
        .map_err(|_| eyre!("source chain id does not fit into u64"))?;
    let destination_chain_id =
        u64::try_from(U256::from_be_bytes(slice_to_32_bytes(&data[96..128])?))
            .map_err(|_| eyre!("destination chain id does not fit into u64"))?;
    let deposit_index = u64::try_from(U256::from_be_bytes(slice_to_32_bytes(&data[128..160])?))
        .map_err(|_| eyre!("deposit index does not fit into u64"))?;

    Ok(DepositEventRecord {
        deposit_root,
        deposit_index,
        amount,
        recipient,
        source_chain_id,
        destination_chain_id,
    })
}

pub fn build_dev_prover() -> CpuProver {
    match std::env::var("SP1_PROVER") {
        Ok(mode) if mode.eq_ignore_ascii_case("mock") => ProverClient::builder().mock().build(),
        Ok(_) => ProverClient::builder().cpu().build(),
        Err(_) => ProverClient::builder().mock().build(),
    }
}

fn slice_to_32_bytes(bytes: &[u8]) -> Result<[u8; 32]> {
    bytes.try_into().map_err(|_| eyre!("expected a 32-byte word, got {} bytes", bytes.len()))
}
