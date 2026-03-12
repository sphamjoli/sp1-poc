use alloy::{
    primitives::{keccak256, Address, Bytes, B256, U256},
    rpc::types::TransactionReceipt,
};
use chain_manager::api::{ChainManagerClient, ReceiptWithProof};
use clap::Parser;
use eyre::{eyre, Result, WrapErr};
use jsonrpsee::http_client::{HttpClient, HttpClientBuilder};
use serde::{Deserialize, Serialize};
use sp1_db::repository::{BridgeEvent, BridgeRepository, EventRepository};
use std::{collections::BTreeMap, fs, path::PathBuf};
use tokio::time::{sleep, Duration};
use tracing::{error, info, warn};
use validator_utils::{
    bindings::{BridgeAttestation, IValidatorManager, RootParams},
    crypto::{parse_u256_hex, sign_attestation, unix_timestamp},
    providers::{read_provider, signer_provider},
    runtime::LoadedRuntime,
    DevValidator, DEFAULT_RUNTIME_CONFIG,
};

#[derive(Debug, Parser)]
#[command(name = "bridge-validator")]
#[command(about = "Local bridge validator runtime")]
struct CommandLineInterface {
    #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG, env = "RUNTIME_CONFIG")]
    config: String,
    #[arg(long)]
    validator: String,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct ValidatorProcessState {
    validator: String,
    #[serde(rename = "lastHeartbeatAt")]
    last_heartbeat_at: Option<u64>,
    #[serde(rename = "lastError")]
    last_error: Option<String>,
    entries: BTreeMap<String, DepositProcessingState>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DepositProcessingState {
    status: String,
    #[serde(rename = "retryCount")]
    retry_count: u32,
    #[serde(rename = "nextRetryAt")]
    next_retry_at: Option<u64>,
    #[serde(rename = "lastError")]
    last_error: Option<String>,
    #[serde(rename = "submittedAt")]
    submitted_at: Option<u64>,
    #[serde(rename = "transactionHash")]
    transaction_hash: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CertificateResponseBody {
    #[serde(rename = "certificateHex")]
    certificate_hex: String,
}

#[derive(Debug)]
struct ValidatorRunner {
    runtime: LoadedRuntime,
    validator: DevValidator,
    node_manager_client: reqwest::Client,
    chain_manager_client: HttpClient,
    state_path: PathBuf,
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();
    tracing_subscriber::fmt().init();

    let command_line_interface = CommandLineInterface::parse();
    let runtime = LoadedRuntime::load(command_line_interface.config)?;
    let validator = runtime.validator_catalog.by_name(&command_line_interface.validator)?.clone();
    let runner = ValidatorRunner::new(runtime, validator)?;
    runner.run().await
}

impl ValidatorRunner {
    fn new(runtime: LoadedRuntime, validator: DevValidator) -> Result<Self> {
        let node_manager_client = reqwest::Client::builder().build()?;
        let chain_manager_client = HttpClientBuilder::default()
            .build(format!("http://{}", runtime.config.services.chain_manager.bind))?;
        let state_path = runtime.state_path(format!("validators/{}.json", validator.name));
        Ok(Self { runtime, validator, node_manager_client, chain_manager_client, state_path })
    }

    async fn run(self) -> Result<()> {
        self.runtime.ensure_runtime_directories()?;
        let mut process_state = self.load_state()?;
        loop {
            let current_timestamp = unix_timestamp()?;
            process_state.last_heartbeat_at = Some(current_timestamp);
            process_state.last_error = None;

            match self.poll_once(&mut process_state).await {
                Ok(()) => {
                    process_state.last_error = None;
                }
                Err(error) => {
                    process_state.last_error = Some(error.to_string());
                    error!(validator = %self.validator.name, ?error, "validator poll failed");
                }
            }

            self.persist_state(&process_state)?;
            sleep(Duration::from_secs(self.runtime.config.services.validator.poll_interval_secs))
                .await;
        }
    }

    async fn poll_once(&self, process_state: &mut ValidatorProcessState) -> Result<()> {
        let deposits = self.fetch_candidate_deposits().await?;
        for deposit in deposits {
            let cursor = self.cursor_key(&deposit)?;
            if self.should_skip(process_state, &cursor).await? {
                continue;
            }

            match self.process_deposit(&deposit).await {
                Ok(()) => {
                    process_state.entries.insert(
                        cursor,
                        DepositProcessingState {
                            status: "submitted".to_owned(),
                            retry_count: 0,
                            next_retry_at: None,
                            last_error: None,
                            submitted_at: Some(unix_timestamp()?),
                            transaction_hash: Some(deposit.transaction_hash.clone()),
                        },
                    );
                }
                Err(error) => {
                    let current_timestamp = unix_timestamp()?;
                    let entry = process_state.entries.entry(cursor).or_insert_with(|| {
                        DepositProcessingState {
                            status: "pending".to_owned(),
                            retry_count: 0,
                            next_retry_at: None,
                            last_error: None,
                            submitted_at: None,
                            transaction_hash: Some(deposit.transaction_hash.clone()),
                        }
                    });
                    entry.retry_count += 1;
                    entry.last_error = Some(error.to_string());
                    entry.next_retry_at = Some(
                        current_timestamp
                            + backoff_seconds(
                                entry.retry_count,
                                self.runtime.config.services.validator.max_backoff_secs,
                            ),
                    );
                    warn!(validator = %self.validator.name, cursor = %entry.transaction_hash.clone().unwrap_or_default(), error = %error, "deposit processing failed");
                }
            }
        }
        Ok(())
    }

    async fn process_deposit(&self, deposit: &BridgeEvent) -> Result<()> {
        let source_chain_id = parse_u64(&deposit.source_chain)?;
        let destination_chain_id = parse_u64(&deposit.destination_chain)?;
        let transaction_hash = parse_b256(&deposit.transaction_hash)?;
        let block_number = parse_u64(&deposit.block_number)?;
        let expected_deposit_root = parse_b256(&deposit.deposit_root)?;
        let expected_deposit_index = parse_u64(&deposit.deposit_index)?;
        let expected_amount = parse_u256(&deposit.amount)?;
        let expected_recipient = parse_address(&deposit.to)?;

        let header = self
            .chain_manager_client
            .finalised_header(
                source_chain_id,
                alloy::rpc::types::BlockNumberOrTag::Number(block_number),
            )
            .await
            .wrap_err("failed to fetch finalized header")?;
        let receipt_with_proof = self
            .chain_manager_client
            .receipt_proof(source_chain_id, transaction_hash)
            .await
            .wrap_err("failed to fetch receipt proof")?
            .ok_or_else(|| eyre!("missing receipt proof for {}", deposit.transaction_hash))?;

        self.verify_deposit_receipt(
            &receipt_with_proof,
            transaction_hash,
            source_chain_id,
            destination_chain_id,
            expected_deposit_root,
            expected_deposit_index,
            expected_amount,
            expected_recipient,
        )?;
        if receipt_with_proof.header.state_root != header.state_root {
            return Err(eyre!("receipt proof header state root does not match finalized header"));
        }

        let certificate_bytes = self.request_certificate(destination_chain_id).await?;
        let timestamp = unix_timestamp()?;
        let signed_attestation = sign_attestation(
            &self.validator,
            source_chain_id,
            block_number,
            expected_deposit_root,
            header.state_root,
            timestamp,
        )?;
        let attestation = BridgeAttestation {
            blockNumber: U256::from(block_number),
            bridgeRoot: expected_deposit_root,
            stateRoot: header.state_root,
            sourceChainId: U256::from(source_chain_id),
            timestamp: U256::from(timestamp),
            validator: self.validator.address()?,
            certificate: certificate_bytes,
            signature: [
                parse_u256_hex(&signed_attestation.signature[0])?,
                parse_u256_hex(&signed_attestation.signature[1])?,
            ],
        };

        match self.submit_attestation(destination_chain_id, attestation.clone()).await {
            Ok(()) => Ok(()),
            Err(error) => {
                let error_message = error.to_string();
                if error_message.contains("AlreadyAttested") {
                    return Ok(());
                }
                if error_message.contains("CertificateExpired") || error_message.contains("nonce") {
                    let refreshed_certificate =
                        self.request_certificate(destination_chain_id).await?;
                    let refreshed_timestamp = unix_timestamp()?;
                    let refreshed_signature = sign_attestation(
                        &self.validator,
                        source_chain_id,
                        block_number,
                        expected_deposit_root,
                        header.state_root,
                        refreshed_timestamp,
                    )?;
                    let refreshed_attestation = BridgeAttestation {
                        blockNumber: U256::from(block_number),
                        bridgeRoot: expected_deposit_root,
                        stateRoot: header.state_root,
                        sourceChainId: U256::from(source_chain_id),
                        timestamp: U256::from(refreshed_timestamp),
                        validator: self.validator.address()?,
                        certificate: refreshed_certificate,
                        signature: [
                            parse_u256_hex(&refreshed_signature.signature[0])?,
                            parse_u256_hex(&refreshed_signature.signature[1])?,
                        ],
                    };
                    return self
                        .submit_attestation(destination_chain_id, refreshed_attestation)
                        .await;
                }

                if self
                    .is_root_verified(
                        destination_chain_id,
                        source_chain_id,
                        block_number,
                        expected_deposit_root,
                        header.state_root,
                    )
                    .await?
                {
                    return Ok(());
                }

                Err(error)
            }
        }
    }

    async fn fetch_candidate_deposits(&self) -> Result<Vec<BridgeEvent>> {
        let endpoint = self.runtime.config.indexer.hasura_url.clone();
        let secret = self.runtime.config.indexer.hasura_secret.clone();
        let source_chain_ids: Vec<u64> =
            self.runtime.config.chains.iter().map(|chain| chain.id).collect();
        let configured_destination_chain_ids: Vec<u64> = source_chain_ids.clone();

        let deposits = tokio::task::spawn_blocking(move || -> Result<Vec<BridgeEvent>, String> {
            let mut repository =
                BridgeRepository::new(endpoint, secret).map_err(|error| error.to_string())?;
            let mut deposits = Vec::new();
            for source_chain_id in source_chain_ids {
                let mut events = repository
                    .get_deposit_events(source_chain_id)
                    .map_err(|error| error.to_string())?;
                deposits.append(&mut events);
            }
            Ok(deposits)
        })
        .await
        .map_err(|error| eyre!(error.to_string()))?
        .map_err(|error| eyre!(error))?;

        let mut filtered_deposits = Vec::new();
        for deposit in deposits {
            let destination_chain_id = parse_u64(&deposit.destination_chain)?;
            let source_chain_id = parse_u64(&deposit.source_chain)?;
            if destination_chain_id == source_chain_id {
                continue;
            }
            if configured_destination_chain_ids.contains(&destination_chain_id) {
                filtered_deposits.push(deposit);
            }
        }
        Ok(filtered_deposits)
    }

    fn verify_deposit_receipt(
        &self,
        receipt_with_proof: &ReceiptWithProof,
        transaction_hash: B256,
        expected_source_chain_id: u64,
        expected_destination_chain_id: u64,
        expected_deposit_root: B256,
        expected_deposit_index: u64,
        expected_amount: U256,
        expected_recipient: Address,
    ) -> Result<()> {
        if !receipt_with_proof.receipt.status() {
            return Err(eyre!("deposit transaction {} did not succeed", transaction_hash));
        }

        let deposit_log = receipt_with_proof
            .receipt
            .inner
            .logs()
            .iter()
            .find(|log| log.topics().first() == Some(&deposit_topic0()))
            .ok_or_else(|| eyre!("deposit event not found in receipt {}", transaction_hash))?;

        let log_topics = deposit_log.topics();
        let log_data = deposit_log.data().data.as_ref();
        if log_topics.get(3).copied().unwrap_or_default() != expected_deposit_root {
            return Err(eyre!("deposit root mismatch"));
        }

        let amount = U256::from_be_bytes::<32>(slice_to_32_bytes(&log_data[0..32])?);
        let recipient = Address::from_slice(&log_data[44..64]);
        let source_chain_id =
            U256::from_be_bytes::<32>(slice_to_32_bytes(&log_data[64..96])?).to::<u64>();
        let destination_chain_id =
            U256::from_be_bytes::<32>(slice_to_32_bytes(&log_data[96..128])?).to::<u64>();
        let deposit_index =
            U256::from_be_bytes::<32>(slice_to_32_bytes(&log_data[128..160])?).to::<u64>();

        if amount != expected_amount {
            return Err(eyre!("deposit amount mismatch"));
        }
        if recipient != expected_recipient {
            return Err(eyre!("deposit recipient mismatch"));
        }
        if source_chain_id != expected_source_chain_id {
            return Err(eyre!("source chain mismatch"));
        }
        if destination_chain_id != expected_destination_chain_id {
            return Err(eyre!("destination chain mismatch"));
        }
        if deposit_index != expected_deposit_index {
            return Err(eyre!("deposit index mismatch"));
        }

        Ok(())
    }

    async fn request_certificate(&self, target_chain_id: u64) -> Result<Bytes> {
        let response = self
            .node_manager_client
            .post(format!("http://{}/certificates", self.runtime.config.services.node_manager.bind))
            .json(&serde_json::json!({
                "validator": self.validator.address()?,
                "targetChainId": target_chain_id
            }))
            .send()
            .await
            .wrap_err("failed to request certificate")?;

        if !response.status().is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(eyre!("node-manager rejected certificate request: {}", body));
        }

        let body: CertificateResponseBody =
            response.json().await.wrap_err("failed to decode certificate response")?;
        let raw_bytes = hex::decode(body.certificate_hex.trim_start_matches("0x"))
            .wrap_err("invalid certificate hex from node-manager")?;
        Ok(Bytes::from(raw_bytes))
    }

    async fn submit_attestation(
        &self,
        destination_chain_id: u64,
        attestation: BridgeAttestation,
    ) -> Result<()> {
        let destination_chain = self.runtime.chain(destination_chain_id)?;
        let deploy_addresses = self.runtime.deployment(destination_chain_id)?;
        let provider = signer_provider(destination_chain, self.validator.evm_signer()?).await?;
        let validator_manager =
            IValidatorManager::new(deploy_addresses.validator_manager, provider);
        let receipt = validator_manager
            .submitAttestation(attestation)
            .send()
            .await
            .wrap_err("failed to submit attestation transaction")?
            .get_receipt()
            .await
            .wrap_err("failed waiting for attestation transaction receipt")?;
        ensure_successful_receipt("attestation submission", &receipt)?;
        info!(validator = %self.validator.name, destination_chain_id, "submitted attestation");
        Ok(())
    }

    async fn is_root_verified(
        &self,
        destination_chain_id: u64,
        source_chain_id: u64,
        block_number: u64,
        bridge_root: B256,
        state_root: B256,
    ) -> Result<bool> {
        let destination_chain = self.runtime.chain(destination_chain_id)?;
        let deploy_addresses = self.runtime.deployment(destination_chain_id)?;
        let provider = read_provider(destination_chain).await?;
        let validator_manager =
            IValidatorManager::new(deploy_addresses.validator_manager, provider);
        let root_params = RootParams {
            blockNumber: U256::from(block_number),
            bridgeRoot: bridge_root,
            stateRoot: state_root,
            sourceChainId: U256::from(source_chain_id),
        };
        validator_manager
            .isRootVerified(root_params)
            .call()
            .await
            .map_err(|error| eyre!(error.to_string()))
    }

    fn cursor_key(&self, deposit: &BridgeEvent) -> Result<String> {
        Ok(format!(
            "{}:{}:{}:{}",
            deposit.source_chain,
            deposit.transaction_hash,
            deposit.deposit_index,
            deposit.destination_chain,
        ))
    }

    async fn should_skip(
        &self,
        process_state: &ValidatorProcessState,
        cursor: &str,
    ) -> Result<bool> {
        if let Some(entry) = process_state.entries.get(cursor) {
            if entry.status == "submitted" || entry.status == "completed" {
                return Ok(true);
            }
            if let Some(next_retry_at) = entry.next_retry_at {
                return Ok(unix_timestamp()? < next_retry_at);
            }
        }
        Ok(false)
    }

    fn load_state(&self) -> Result<ValidatorProcessState> {
        if !self.state_path.exists() {
            return Ok(ValidatorProcessState {
                validator: self.validator.name.clone(),
                ..ValidatorProcessState::default()
            });
        }
        let bytes = fs::read(&self.state_path)
            .wrap_err_with(|| format!("failed to read {}", self.state_path.display()))?;
        let state: ValidatorProcessState = serde_json::from_slice(&bytes)
            .wrap_err_with(|| format!("invalid validator state {}", self.state_path.display()))?;
        Ok(state)
    }

    fn persist_state(&self, process_state: &ValidatorProcessState) -> Result<()> {
        if let Some(parent_directory) = self.state_path.parent() {
            fs::create_dir_all(parent_directory)
                .wrap_err_with(|| format!("failed to create {}", parent_directory.display()))?;
        }
        fs::write(&self.state_path, serde_json::to_vec_pretty(process_state)?)
            .wrap_err_with(|| format!("failed to write {}", self.state_path.display()))?;
        Ok(())
    }
}

fn parse_b256(value: &str) -> Result<B256> {
    value.parse::<B256>().map_err(|error| eyre!(error.to_string()))
}

fn parse_address(value: &str) -> Result<Address> {
    value.parse::<Address>().map_err(|error| eyre!(error.to_string()))
}

fn parse_u256(value: &str) -> Result<U256> {
    let trimmed_value = value.trim();
    let maybe_hex = trimmed_value.strip_prefix("0x").or_else(|| trimmed_value.strip_prefix("0X"));
    if let Some(hex_value) = maybe_hex {
        Ok(U256::from_str_radix(hex_value, 16)?)
    } else {
        Ok(U256::from_str_radix(trimmed_value, 10)?)
    }
}

fn parse_u64(value: &str) -> Result<u64> {
    let trimmed_value = value.trim();
    let maybe_hex = trimmed_value.strip_prefix("0x").or_else(|| trimmed_value.strip_prefix("0X"));
    if let Some(hex_value) = maybe_hex {
        Ok(u64::from_str_radix(hex_value, 16)?)
    } else {
        Ok(trimmed_value.parse::<u64>()?)
    }
}

fn slice_to_32_bytes(bytes: &[u8]) -> Result<[u8; 32]> {
    bytes.try_into().map_err(|_| eyre!("expected 32-byte ABI word, got {} bytes", bytes.len()))
}

fn deposit_topic0() -> B256 {
    keccak256(b"Deposit(address,uint256,address,address,uint256,uint256,uint256,bytes32)")
}

fn ensure_successful_receipt(action: &str, receipt: &TransactionReceipt) -> Result<()> {
    if receipt.status() {
        return Ok(());
    }

    Err(eyre!("{} reverted in transaction {}", action, receipt.transaction_hash))
}

fn backoff_seconds(retry_count: u32, max_backoff_seconds: u64) -> u64 {
    let exponential = 2u64.saturating_pow(retry_count.min(8));
    exponential.min(max_backoff_seconds.max(1))
}

#[cfg(test)]
mod tests {
    use super::{backoff_seconds, deposit_topic0, slice_to_32_bytes};

    #[test]
    fn deposit_topic_matches_expected_signature_hash() {
        assert_eq!(
            format!("{:#x}", deposit_topic0()),
            "0xd7c17b332b8f37e92a6a0eb64c447cad41d1c6c7a7e8bf6012970b44ab7ef00c"
        );
    }

    #[test]
    fn backoff_is_capped() {
        assert_eq!(backoff_seconds(1, 30), 2);
        assert_eq!(backoff_seconds(4, 30), 16);
        assert_eq!(backoff_seconds(8, 30), 30);
    }

    #[test]
    fn abi_word_parser_requires_thirty_two_bytes() {
        assert!(slice_to_32_bytes(&[0u8; 31]).is_err());
        assert!(slice_to_32_bytes(&[0u8; 32]).is_ok());
    }
}
