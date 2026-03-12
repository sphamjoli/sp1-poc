use alloy::rpc::types::TransactionReceipt;
use eyre::{eyre, Result};

pub fn ensure_successful_receipt(action: &str, receipt: &TransactionReceipt) -> Result<()> {
    if receipt.status() {
        return Ok(());
    }

    Err(eyre!("{} reverted in transaction {}", action, receipt.transaction_hash))
}
