//! End-to-end test for the bridge co-processor proof pipeline.
//!
//! Runs against two local Anvil chains that are pre-deployed by `make deploy-local`.
//! The test mirrors the two-fork setup in `contracts/test/base/BridgeBase.t.sol`:
//! satellite chain (id=31338) receives deposits; base chain (id=31339) is the hub.
//!
//! Run with `make test-e2e`.  Required environment variables:
//!
//! - `RPC_URL_31338` – satellite chain RPC (default: `http://127.0.0.1:8545`)
//! - `RPC_URL_31339` – base chain RPC (default: `http://127.0.0.1:8546`)
//! - `SP1_PROVER`   – `mock` (fast, no real ZK) or `local`/`network` for production

use alloy::{
    eips::eip2718::Encodable2718,
    network::EthereumWallet,
    providers::{Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
    sol,
    sol_types::SolCall,
};
use alloy_consensus::Header;
use alloy_primitives::{Address, Bytes, B256, U256};
use alloy_rpc_types::{BlockNumberOrTag, TransactionRequest};
use bridge_script::{
    build_dev_prover, deposit_event_signature, parse_deposit_event, DepositEventRecord,
};
use chain_manager::api::{ChainConfig, ChainManagerClient, ChainManagerImpl, ReceiptWithProof};
use clap::Parser;
use sp1_sdk::{include_elf, Prover, SP1Stdin};
use sp1_types::{
    BatchInput, DepositExpectation, FieldAddress, FieldB256, FieldLocation, FieldU256, FieldU64,
    ReceiptWitness, ZkvmInput,
};
use std::{collections::HashMap, env, fs};

pub const BRIDGE_ELF: &[u8] = include_elf!("bridge-program");

const SATELLITE_CHAIN_ID: u64 = 31338;
const BASE_CHAIN_ID: u64 = 31339;
/// Anvil account 0 — pre-funded with 10,000 ETH and token supply by the deploy script.
const ANVIL_PRIVATE_KEY: &str =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const DEPOSIT_AMOUNT: u128 = 1_000_000_000_000_000_000; // 1 ETH in wei

#[derive(Parser, Debug)]
#[command(author, version, about = "Bridge end-to-end pipeline runner")]
struct CliArgs {
    /// Optional path for writing scenario output as JSON.
    #[arg(long)]
    json_out: Option<String>,
}

#[derive(Debug, serde::Serialize)]
struct BridgeScenarioReport {
    rpc_url_satellite: String,
    rpc_url_base: String,
    bridge_address: Address,
    token_address: Address,
    deposit_tx_hash: B256,
    deposit_block_number: u64,
    deposit_root: B256,
    deposit_index: u64,
    amount_wei: U256,
    prover_backend: String,
}

// ---------------------------------------------------------------------------
// ABI stubs
// ---------------------------------------------------------------------------

sol! {
    interface IERC20 {
        function approve(address spender, uint256 amount) external returns (bool);
    }

    interface IBridge {
        struct DepositParams {
            uint256 amount;
            address token;
            address to;
            uint256 destinationChain;
        }

        function deposit(DepositParams calldata params) external payable;

        event Deposit(
            address indexed who,
            uint256 amount,
            address indexed token,
            address to,
            uint256 sourceChain,
            uint256 destinationChain,
            uint256 depositIndex,
            bytes32 indexed depositRoot
        );
    }
}

// ---------------------------------------------------------------------------
// Bridge test runner
// ---------------------------------------------------------------------------

/// Orchestrates the full deposit → receipt-proof → Groth16 proof pipeline.
struct BridgeTestRunner {
    /// RPC endpoint for the satellite chain (chain id=1, deposits originate here).
    rpc_url_satellite: String,
    /// RPC endpoint for the base (hub) chain (chain id=8453).
    rpc_url_base: String,
}

impl BridgeTestRunner {
    /// Builds a [`BridgeTestRunner`] from environment variables, falling back
    /// to the default Anvil ports used by `make deploy-local`.
    fn from_env() -> Self {
        Self {
            rpc_url_satellite: env::var("RPC_URL_31338")
                .unwrap_or_else(|_| "http://127.0.0.1:8545".to_string()),
            rpc_url_base: env::var("RPC_URL_31339")
                .unwrap_or_else(|_| "http://127.0.0.1:8546".to_string()),
        }
    }

    /// Executes the full pipeline: approve → deposit → proof → verify.
    async fn run(self) -> Result<BridgeScenarioReport, Box<dyn std::error::Error>> {
        // Start chain-manager on port 3001 (port 3000 is reserved for production).
        tracing::info!("starting chain-manager on 127.0.0.1:3001");
        let configs = vec![
            ChainConfig { rpc_url: self.rpc_url_satellite.clone(), chain_id: SATELLITE_CHAIN_ID },
            ChainConfig { rpc_url: self.rpc_url_base.clone(), chain_id: BASE_CHAIN_ID },
        ];
        let (_server_handle, chain_client) =
            ChainManagerImpl::new(configs).create_start_server("127.0.0.1:3001").await?;

        let bridge_address = read_deploy_address(SATELLITE_CHAIN_ID, "bridge");
        let token_address = read_deploy_address(SATELLITE_CHAIN_ID, "tokenA");
        tracing::info!(%bridge_address, %token_address, "loaded deployed contract addresses");

        let signer: PrivateKeySigner = ANVIL_PRIVATE_KEY.parse()?;
        let depositor = signer.address();
        let provider = ProviderBuilder::new()
            .wallet(EthereumWallet::from(signer))
            .connect_http(self.rpc_url_satellite.parse()?);

        // Approve the bridge to pull tokens from the depositor.
        self.approve_bridge(&provider, token_address, bridge_address).await?;

        // Submit the deposit and wait for it to be mined.
        let deposit_tx_hash =
            self.submit_deposit(&provider, bridge_address, token_address, depositor).await?;
        tracing::info!(%deposit_tx_hash, "deposit transaction mined");

        let receipt = provider
            .get_transaction_receipt(deposit_tx_hash)
            .await?
            .unwrap_or_else(|| panic!("no receipt for {deposit_tx_hash}"));

        let block_number = receipt.block_number.expect("receipt missing block_number");
        tracing::info!(block_number, "deposit confirmed in block");

        let event = parse_deposit_event(&receipt)?;

        // Fetch the MPT receipt proof from the chain-manager.
        tracing::info!(block_number, "fetching receipt MPT proofs");
        let all_receipts_with_proofs: HashMap<B256, ReceiptWithProof> =
            chain_client.block_receipts_with_proofs(SATELLITE_CHAIN_ID, block_number).await?;
        let header: Header = chain_client
            .finalised_header(SATELLITE_CHAIN_ID, BlockNumberOrTag::Number(block_number))
            .await?;

        let receipt_with_proof = all_receipts_with_proofs
            .get(&deposit_tx_hash)
            .unwrap_or_else(|| panic!("proof not found for {deposit_tx_hash}"));

        let zkvm_input =
            build_zkvm_input(bridge_address, &event, receipt_with_proof, block_number, &header);

        let prover_backend = prove_and_verify(zkvm_input)?;

        println!("✓  Bridge end-to-end test passed!");
        println!("   Block:   {block_number}");
        println!("   Amount:  {} wei of {token_address}", event.amount);
        println!("   Root:    {}", event.deposit_root);
        println!("   Index:   {}", event.deposit_index);

        Ok(BridgeScenarioReport {
            rpc_url_satellite: self.rpc_url_satellite,
            rpc_url_base: self.rpc_url_base,
            bridge_address,
            token_address,
            deposit_tx_hash,
            deposit_block_number: block_number,
            deposit_root: event.deposit_root,
            deposit_index: event.deposit_index,
            amount_wei: event.amount,
            prover_backend,
        })
    }

    /// Approves the bridge to spend `DEPOSIT_AMOUNT` tokens.
    async fn approve_bridge<P: Provider>(
        &self,
        provider: &P,
        token_address: Address,
        bridge_address: Address,
    ) -> Result<(), Box<dyn std::error::Error>> {
        tracing::info!("approving bridge to spend tokens");
        let calldata =
            IERC20::approveCall { spender: bridge_address, amount: U256::from(DEPOSIT_AMOUNT) }
                .abi_encode();
        send_and_wait(provider, token_address, calldata).await?;
        Ok(())
    }

    /// Submits a deposit transaction and returns its hash.
    async fn submit_deposit<P: Provider>(
        &self,
        provider: &P,
        bridge_address: Address,
        token_address: Address,
        depositor: Address,
    ) -> Result<B256, Box<dyn std::error::Error>> {
        tracing::info!("submitting deposit to bridge");
        let calldata = IBridge::depositCall {
            params: IBridge::DepositParams {
                amount: U256::from(DEPOSIT_AMOUNT),
                token: token_address,
                to: depositor,
                destinationChain: U256::from(BASE_CHAIN_ID),
            },
        }
        .abi_encode();
        send_and_wait(provider, bridge_address, calldata).await
    }
}

// ---------------------------------------------------------------------------
// Module-level helpers
// ---------------------------------------------------------------------------

/// Reads a deployed contract address from `contracts/deploy-out/{chain_id}.json`.
///
/// The forge deploy script writes addresses under keys `"bridge"`, `"tokenA"`,
/// `"tokenB"`, `"stakeManager"`, and `"validatorManager"`.
///
/// # Panics
///
/// Panics if the deploy-out file is missing or the requested key is absent.
fn read_deploy_address(chain_id: u64, key: &str) -> Address {
    let path = format!("contracts/deploy-out/{chain_id}.json");
    let raw = fs::read_to_string(&path)
        .unwrap_or_else(|_| panic!("{path} not found — run `make deploy-local` first"));
    let json: serde_json::Value = serde_json::from_str(&raw).expect("invalid JSON in deploy-out");
    json[key]
        .as_str()
        .unwrap_or_else(|| panic!("key '{key}' missing from {path}"))
        .parse()
        .unwrap_or_else(|error| panic!("bad address for '{key}' in {path}: {error}"))
}

/// Sends `calldata` to `to` and waits for the transaction to be mined.
///
/// Uses raw [`TransactionRequest`] to avoid the generic network-type inference
/// issues that arise with the `sol!` call builders.
async fn send_and_wait<P: Provider>(
    provider: &P,
    to: Address,
    calldata: Vec<u8>,
) -> Result<B256, Box<dyn std::error::Error>> {
    let request = TransactionRequest::default().to(to).input(calldata.into());
    let tx_hash = provider.send_transaction(request).await?.watch().await?;
    Ok(tx_hash)
}

/// Constructs a [`ZkvmInput`] from the deposit receipt proof and event fields.
fn build_zkvm_input(
    bridge_address: Address,
    event: &DepositEventRecord,
    receipt_with_proof: &ReceiptWithProof,
    block_number: u64,
    header: &Header,
) -> ZkvmInput {
    let mut receipt_buf = Vec::new();
    receipt_with_proof
        .receipt
        .inner
        .clone()
        .into_primitives_receipt()
        .encode_2718(&mut receipt_buf);

    let expected = DepositExpectation {
        bridge: bridge_address,
        topic0: deposit_event_signature(),
        deposit_root: FieldB256 { value: event.deposit_root, location: FieldLocation::Topic(3) },
        deposit_index: FieldU64 {
            value: event.deposit_index,
            location: FieldLocation::DataWord(4),
        },
        amount: FieldU256 { value: event.amount, location: FieldLocation::DataWord(0) },
        to: FieldAddress { value: event.recipient, location: FieldLocation::DataWord(1) },
    };

    let witness = ReceiptWitness {
        tx_index: receipt_with_proof.transaction_index,
        receipt_envelope: Bytes::from(receipt_buf),
        proof_nodes_rlp: receipt_with_proof.proof_nodes.clone(),
        expected,
    };

    let deposit_batch = BatchInput {
        chain_id: SATELLITE_CHAIN_ID,
        block_number,
        receipts_root: header.receipts_root,
        header_hash: Some(header.hash_slow()),
        receipts: vec![witness],
    };

    ZkvmInput {
        attested_chain_id: SATELLITE_CHAIN_ID,
        deposit_batch,
        attestations: vec![],
        slash_amount: U256::ZERO,
    }
}

/// Generates a Groth16 proof for `zkvm_input` and verifies it locally.
///
/// The proving backend is selected by the `SP1_PROVER` environment variable:
///
/// | Value     | Behaviour                                       |
/// |-----------|------------------------------------------------|
/// | `mock`    | Fast mock Groth16 proof — no real ZK (default) |
/// | `local`   | Real Groth16 proof on the local CPU (slow)     |
/// | `network` | Delegates to Succinct's proving network        |
fn prove_and_verify(zkvm_input: ZkvmInput) -> Result<String, Box<dyn std::error::Error>> {
    let backend = env::var("SP1_PROVER").unwrap_or_else(|_| "mock".to_string());
    tracing::info!(%backend, "generating SP1 Groth16 proof");

    let client = build_dev_prover();
    let (proving_key, verifying_key) = client.setup(BRIDGE_ELF);

    let mut stdin = SP1Stdin::new();
    stdin.write(&zkvm_input);

    let proof = client.prove(&proving_key, &stdin).groth16().run()?;
    client.verify(&proof, &verifying_key)?;
    tracing::info!("proof verified");
    Ok(backend)
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    sp1_sdk::utils::setup_logger();
    let cli = CliArgs::parse();
    let report = BridgeTestRunner::from_env().run().await?;

    if let Some(json_out) = cli.json_out {
        let payload = serde_json::to_string_pretty(&report)?;
        fs::write(&json_out, format!("{payload}\n"))?;
        println!("   JSON:    {json_out}");
    }

    Ok(())
}
