use alloy::eips::eip2718::Encodable2718;
use alloy_consensus::Header;
use alloy_primitives::{keccak256, Address, Bytes, B256, U256};
use alloy_rpc_types::BlockNumberOrTag;
use alloy_rpc_types::TransactionReceipt;
use bridge_script::build_dev_prover;
use chain_manager::api::ChainManagerClient;
use clap::{Parser, ValueEnum};
use jsonrpsee::http_client::{HttpClient, HttpClientBuilder};
use sp1_db::repository::{BridgeAttestationEvent, BridgeEvent, BridgeRepository, EventRepository};
use sp1_sdk::{include_elf, Prover, SP1ProofWithPublicValues, SP1Stdin};
use sp1_types::{
    AttestationWitness, BatchInput, DepositExpectation, FieldAddress, FieldB256, FieldLocation,
    FieldU256, FieldU64, ReceiptWitness, ZkvmInput,
};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::PathBuf,
    time::Duration,
};
use tracing::{error, info, warn};
use validator_utils::{
    bindings::{IValidatorManager, VerificationParams},
    providers::signer_provider,
    write_state_file, LoadedRuntime, DEFAULT_RUNTIME_CONFIG,
};

pub const BRIDGE_ELF: &[u8] = include_elf!("bridge-program");
const DEFAULT_SLASH_AMOUNT: u64 = 10_000_000_000_000_000;

#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Ord, ValueEnum, Debug)]
enum ProofSystem {
    Plonk,
    Groth16,
}

#[derive(Debug, Parser)]
#[command(name = "bridge-script")]
#[command(about = "SP1 bridge proof and finalization loop")]
struct CommandLineInterface {
    #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG, env = "RUNTIME_CONFIG")]
    config: String,
    #[arg(long, value_enum, default_value = "groth16")]
    system: ProofSystem,
    #[arg(long)]
    r#loop: bool,
    #[arg(long)]
    interval_secs: Option<u64>,
}

#[derive(Debug, Default, serde::Deserialize, serde::Serialize)]
struct Sp1LoopState {
    processed_transactions: BTreeSet<String>,
    last_run_at: Option<u64>,
    last_finalized_source_chain_id: Option<u64>,
    last_finalized_block_number: Option<u64>,
    last_error: Option<String>,
}

#[derive(Debug, serde::Serialize)]
struct Sp1Heartbeat {
    status: &'static str,
    #[serde(rename = "startedAt")]
    started_at: u64,
    #[serde(rename = "lastRunAt")]
    last_run_at: Option<u64>,
    #[serde(rename = "lastFinalizedSourceChainId")]
    last_finalized_source_chain_id: Option<u64>,
    #[serde(rename = "lastFinalizedBlockNumber")]
    last_finalized_block_number: Option<u64>,
    #[serde(rename = "lastError")]
    last_error: Option<String>,
}

struct Sp1Runner {
    runtime: LoadedRuntime,
    chain_manager_client: HttpClient,
    indexer_url: String,
    indexer_secret: String,
    proof_system: ProofSystem,
    state_path: PathBuf,
    base_validator_manager: Address,
}

impl Sp1Runner {
    async fn new(config_path: String, proof_system: ProofSystem) -> eyre::Result<Self> {
        let runtime = LoadedRuntime::load(config_path)?;
        runtime.ensure_runtime_directories()?;

        let chain_manager_client = HttpClientBuilder::default()
            .build(format!("http://{}", runtime.config.services.chain_manager.bind))?;
        let state_path = runtime.state_path("sp1-state.json");
        let base_validator_manager =
            runtime.deployment(runtime.config.base_chain_id)?.validator_manager;

        Ok(Self {
            indexer_url: runtime.config.indexer.hasura_url.clone(),
            indexer_secret: runtime.config.indexer.hasura_secret.clone(),
            runtime,
            chain_manager_client,
            proof_system,
            state_path,
            base_validator_manager,
        })
    }

    async fn run(mut self, interval_secs: u64, loop_enabled: bool) -> eyre::Result<()> {
        let started_at = validator_utils::unix_timestamp()?;
        let mut state = self.load_state()?;

        loop {
            let run_result = self.run_once(&mut state).await;
            let last_error = match run_result {
                Ok(()) => None,
                Err(ref error) => {
                    let message = error.to_string();
                    error!(error = %message, "sp1 run failed");
                    Some(message)
                }
            };

            state.last_run_at = Some(validator_utils::unix_timestamp()?);
            state.last_error = last_error.clone();
            self.persist_state(&state)?;
            self.write_heartbeat(started_at, &state)?;

            if !loop_enabled {
                return run_result;
            }

            tokio::time::sleep(Duration::from_secs(interval_secs)).await;
        }
    }

    async fn run_once(&mut self, state: &mut Sp1LoopState) -> eyre::Result<()> {
        let base_chain_id = self.runtime.config.base_chain_id;
        let base_attestations = self.load_base_attestations(base_chain_id).await?;

        for source_chain in
            self.runtime.config.chains.iter().filter(|chain| chain.id != base_chain_id)
        {
            let deposits = self.fetch_deposit_events(source_chain.id).await?;
            let grouped_deposits = self.group_unprocessed_deposits(&deposits, state)?;

            for (block_number, block_deposits) in grouped_deposits {
                let expected_bridge_root = expected_bridge_root(&block_deposits)?;
                let deposit_batch = self
                    .build_deposit_batch(source_chain.id, block_number, &block_deposits)
                    .await?;
                let attestation_witnesses = self
                    .build_attestation_witnesses(
                        source_chain.id,
                        block_number,
                        expected_bridge_root,
                        &base_attestations,
                    )
                    .await?;

                if attestation_witnesses.is_empty() {
                    warn!(
                        source_chain_id = source_chain.id,
                        block_number, "no attestation witnesses found"
                    );
                    continue;
                }

                let input = ZkvmInput {
                    attested_chain_id: source_chain.id,
                    deposit_batch,
                    attestations: attestation_witnesses,
                    slash_amount: U256::from(DEFAULT_SLASH_AMOUNT),
                };
                let proof = create_proof(self.proof_system, input).await?;

                self.finalise_attestations(proof).await?;

                for deposit in &block_deposits {
                    state.processed_transactions.insert(deposit.transaction_hash.clone());
                }
                state.last_finalized_source_chain_id = Some(source_chain.id);
                state.last_finalized_block_number = Some(block_number);

                info!(source_chain_id = source_chain.id, block_number, "finalized attested block");
            }
        }

        Ok(())
    }

    fn group_unprocessed_deposits(
        &self,
        deposits: &[BridgeEvent],
        state: &Sp1LoopState,
    ) -> eyre::Result<BTreeMap<u64, Vec<BridgeEvent>>> {
        let mut grouped = BTreeMap::new();

        for deposit in deposits {
            if state.processed_transactions.contains(&deposit.transaction_hash) {
                continue;
            }

            let destination_chain_id = parse_u64(&deposit.destination_chain)?;
            let source_chain_id = parse_u64(&deposit.source_chain)?;
            if destination_chain_id == source_chain_id {
                continue;
            }
            if destination_chain_id != self.runtime.config.base_chain_id {
                continue;
            }

            grouped
                .entry(parse_u64(&deposit.block_number)?)
                .or_insert_with(Vec::new)
                .push(deposit.clone());
        }

        Ok(grouped)
    }

    async fn fetch_deposit_events(&self, chain_id: u64) -> eyre::Result<Vec<BridgeEvent>> {
        let indexer_url = self.indexer_url.clone();
        let indexer_secret = self.indexer_secret.clone();

        tokio::task::spawn_blocking(move || {
            let mut repository = BridgeRepository::new(indexer_url, indexer_secret)
                .map_err(|error| eyre::eyre!(error.to_string()))?;
            repository.get_deposit_events(chain_id).map_err(|error| eyre::eyre!(error.to_string()))
        })
        .await?
    }

    async fn load_base_attestations(
        &self,
        base_chain_id: u64,
    ) -> eyre::Result<Vec<BridgeAttestationEvent>> {
        let indexer_url = self.indexer_url.clone();
        let indexer_secret = self.indexer_secret.clone();
        let attestation_events = tokio::task::spawn_blocking(move || {
            let mut repository = BridgeRepository::new(indexer_url, indexer_secret)
                .map_err(|error| eyre::eyre!(error.to_string()))?;
            let _ = repository
                .get_submitted_attestations(base_chain_id)
                .map_err(|error| eyre::eyre!(error.to_string()))?;
            Ok::<Vec<BridgeAttestationEvent>, eyre::Report>(repository.attestation_events)
        })
        .await??;

        Ok(attestation_events
            .into_iter()
            .filter(|event| {
                event
                    .validator_manager
                    .eq_ignore_ascii_case(&self.base_validator_manager.to_string())
            })
            .collect())
    }

    async fn build_deposit_batch(
        &self,
        source_chain_id: u64,
        block_number: u64,
        deposits: &[BridgeEvent],
    ) -> eyre::Result<BatchInput> {
        let receipt_proofs = self
            .chain_manager_client
            .block_receipts_with_proofs(source_chain_id, block_number)
            .await?;
        let header: Header = self
            .chain_manager_client
            .finalised_header(source_chain_id, BlockNumberOrTag::Number(block_number))
            .await?;
        let bridge_address = self.runtime.deployment(source_chain_id)?.bridge;
        let mut receipts = Vec::new();

        for deposit in deposits {
            let transaction_hash = parse_b256(&deposit.transaction_hash)?;
            let receipt_with_proof = receipt_proofs.get(&transaction_hash).ok_or_else(|| {
                eyre::eyre!("receipt proof missing for {}", deposit.transaction_hash)
            })?;

            let mut receipt_bytes = Vec::new();
            receipt_with_proof
                .receipt
                .inner
                .clone()
                .into_primitives_receipt()
                .encode_2718(&mut receipt_bytes);

            receipts.push(ReceiptWitness {
                tx_index: receipt_with_proof.transaction_index,
                receipt_envelope: Bytes::from(receipt_bytes),
                proof_nodes_rlp: receipt_with_proof.proof_nodes.clone(),
                expected: DepositExpectation {
                    bridge: bridge_address,
                    topic0: deposit_topic0(),
                    deposit_root: FieldB256 {
                        value: parse_b256(&deposit.deposit_root)?,
                        location: FieldLocation::Topic(3),
                    },
                    deposit_index: FieldU64 {
                        value: parse_u64(&deposit.deposit_index)?,
                        location: FieldLocation::DataWord(4),
                    },
                    amount: FieldU256 {
                        value: parse_u256(&deposit.amount)?,
                        location: FieldLocation::DataWord(0),
                    },
                    to: FieldAddress {
                        value: parse_address(&deposit.to)?,
                        location: FieldLocation::DataWord(1),
                    },
                },
            });
        }

        Ok(BatchInput {
            chain_id: source_chain_id,
            block_number,
            receipts_root: header.receipts_root,
            header_hash: Some(header.hash_slow()),
            receipts,
        })
    }

    async fn build_attestation_witnesses(
        &self,
        source_chain_id: u64,
        block_number: u64,
        expected_bridge_root: B256,
        attestation_events: &[BridgeAttestationEvent],
    ) -> eyre::Result<Vec<AttestationWitness>> {
        let mut witnesses = Vec::new();

        for attestation_event in attestation_events {
            if parse_u64(&attestation_event.source_chain_id)? != source_chain_id {
                continue;
            }
            if parse_u64(&attestation_event.block_number)? != block_number {
                continue;
            }
            if parse_b256(&attestation_event.bridge_root)? != expected_bridge_root {
                continue;
            }

            let transaction_hash = parse_b256(&attestation_event.transaction_hash)?;
            let receipt_with_proof = match self
                .chain_manager_client
                .receipt_proof(self.runtime.config.base_chain_id, transaction_hash)
                .await?
            {
                Some(receipt_with_proof) => receipt_with_proof,
                None => {
                    warn!(transaction_hash = %attestation_event.transaction_hash, "attestation receipt proof missing");
                    continue;
                }
            };

            let mut receipt_bytes = Vec::new();
            receipt_with_proof
                .receipt
                .inner
                .clone()
                .into_primitives_receipt()
                .encode_2718(&mut receipt_bytes);

            witnesses.push(AttestationWitness {
                receipts_root: receipt_with_proof.header.receipts_root,
                validator_manager: self.base_validator_manager,
                validator: parse_address(&attestation_event.validator)?,
                source_chain_id,
                bridge_root: parse_b256(&attestation_event.bridge_root)?,
                block_number,
                state_root: parse_b256(&attestation_event.state_root)?,
                timestamp: parse_u64(&attestation_event.timestamp)?,
                tx_index: receipt_with_proof.transaction_index,
                receipt_envelope: Bytes::from(receipt_bytes),
                proof_nodes_rlp: receipt_with_proof.proof_nodes.clone(),
            });
        }

        Ok(witnesses)
    }

    async fn finalise_attestations(&self, proof: SP1ProofWithPublicValues) -> eyre::Result<()> {
        let base_chain = self.runtime.base_chain()?;
        let provider = signer_provider(base_chain, self.runtime.owner_signer()?).await?;
        let validator_manager = IValidatorManager::new(self.base_validator_manager, provider);
        let params = VerificationParams {
            publicValues: Bytes::from(proof.public_values.to_vec()),
            proofBytes: Bytes::from(proof.bytes()),
        };

        let receipt =
            validator_manager.finaliseAttestations(params).send().await?.get_receipt().await?;
        ensure_successful_receipt("attestation finalization", &receipt)?;
        Ok(())
    }

    fn load_state(&self) -> eyre::Result<Sp1LoopState> {
        if !self.state_path.exists() {
            return Ok(Sp1LoopState::default());
        }

        let bytes = fs::read(&self.state_path)?;
        Ok(serde_json::from_slice(&bytes)?)
    }

    fn persist_state(&self, state: &Sp1LoopState) -> eyre::Result<()> {
        if let Some(parent_directory) = self.state_path.parent() {
            fs::create_dir_all(parent_directory)?;
        }
        fs::write(&self.state_path, serde_json::to_vec_pretty(state)?)?;
        Ok(())
    }

    fn write_heartbeat(&self, started_at: u64, state: &Sp1LoopState) -> eyre::Result<()> {
        write_state_file(
            &self.runtime,
            "sp1.json",
            &Sp1Heartbeat {
                status: "ok",
                started_at,
                last_run_at: state.last_run_at,
                last_finalized_source_chain_id: state.last_finalized_source_chain_id,
                last_finalized_block_number: state.last_finalized_block_number,
                last_error: state.last_error.clone(),
            },
        )
    }
}

#[tokio::main]
async fn main() -> eyre::Result<()> {
    dotenv::dotenv().ok();
    tracing_subscriber::fmt().with_target(false).init();

    let command_line_interface = CommandLineInterface::parse();
    let interval_secs = command_line_interface.interval_secs.unwrap_or(60);
    let runner =
        Sp1Runner::new(command_line_interface.config, command_line_interface.system).await?;
    runner.run(interval_secs, command_line_interface.r#loop).await
}

async fn create_proof(
    proof_system: ProofSystem,
    input: ZkvmInput,
) -> eyre::Result<SP1ProofWithPublicValues> {
    tokio::task::spawn_blocking(move || {
        let prover = build_dev_prover();
        let (proving_key, verifying_key) = prover.setup(BRIDGE_ELF);
        let mut stdin = SP1Stdin::new();
        stdin.write(&input);

        let proof = match proof_system {
            ProofSystem::Groth16 => prover
                .prove(&proving_key, &stdin)
                .groth16()
                .run()
                .map_err(|error| eyre::eyre!(error.to_string()))?,
            ProofSystem::Plonk => prover
                .prove(&proving_key, &stdin)
                .plonk()
                .run()
                .map_err(|error| eyre::eyre!(error.to_string()))?,
        };

        prover.verify(&proof, &verifying_key)?;
        Ok::<SP1ProofWithPublicValues, eyre::Report>(proof)
    })
    .await?
}

fn ensure_successful_receipt(action: &str, receipt: &TransactionReceipt) -> eyre::Result<()> {
    if receipt.status() {
        return Ok(());
    }

    Err(eyre::eyre!("{} reverted in transaction {}", action, receipt.transaction_hash))
}

fn expected_bridge_root(deposits: &[BridgeEvent]) -> eyre::Result<B256> {
    deposits
        .iter()
        .max_by_key(|deposit| parse_u64(&deposit.deposit_index).unwrap_or_default())
        .map(|deposit| parse_b256(&deposit.deposit_root))
        .transpose()?
        .ok_or_else(|| eyre::eyre!("expected at least one deposit"))
}

fn parse_address(value: &str) -> eyre::Result<Address> {
    Ok(value.parse::<Address>()?)
}

fn parse_b256(value: &str) -> eyre::Result<B256> {
    Ok(value.parse::<B256>()?)
}

fn parse_u64(value: &str) -> eyre::Result<u64> {
    let trimmed_value = value.trim();
    if let Some(hex_value) =
        trimmed_value.strip_prefix("0x").or_else(|| trimmed_value.strip_prefix("0X"))
    {
        Ok(u64::from_str_radix(hex_value, 16)?)
    } else {
        Ok(trimmed_value.parse::<u64>()?)
    }
}

fn parse_u256(value: &str) -> eyre::Result<U256> {
    let trimmed_value = value.trim();
    if let Some(hex_value) =
        trimmed_value.strip_prefix("0x").or_else(|| trimmed_value.strip_prefix("0X"))
    {
        Ok(U256::from_str_radix(hex_value, 16)?)
    } else {
        Ok(U256::from_str_radix(trimmed_value, 10)?)
    }
}

fn deposit_topic0() -> B256 {
    keccak256(b"Deposit(address,uint256,address,address,uint256,uint256,uint256,bytes32)")
}
