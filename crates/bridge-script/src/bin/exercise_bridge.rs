use alloy::{
    network::TransactionBuilder,
    primitives::{Address, B256, U256},
    providers::Provider,
    rpc::types::BlockNumberOrTag,
    rpc::types::TransactionRequest,
    sol_types::SolCall,
};
use bridge_script::{parse_deposit_event, DepositEventRecord};
use chain_manager::api::ChainManagerClient;
use clap::{Parser, ValueEnum};
use eyre::{bail, eyre, Result, WrapErr};
use jsonrpsee::http_client::HttpClientBuilder;
use serde::Serialize;
use std::{fs, path::PathBuf, time::Instant};
use tokio::time::{sleep, Duration};
use tracing::info;
use validator_utils::{
    bindings::{IBridge, IValidatorManager, RootParams, IERC20},
    providers::{read_provider, signer_provider},
    LoadedRuntime, DEFAULT_RUNTIME_CONFIG,
};

#[derive(Debug, Parser)]
#[command(name = "exercise-bridge")]
#[command(about = "Exercise the live bridge runtime by depositing and claiming across chains")]
struct CommandLineInterface {
    #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG, env = "RUNTIME_CONFIG")]
    config: String,
    #[arg(long)]
    source_chain_id: Option<u64>,
    #[arg(long)]
    destination_chain_id: Option<u64>,
    #[arg(long, value_enum, default_value = "native")]
    asset: AssetMode,
    #[arg(long, default_value_t = 1_000_000_000_000_000_000u128)]
    amount_wei: u128,
    #[arg(long, default_value_t = 180)]
    timeout_secs: u64,
    #[arg(long)]
    json_out: Option<PathBuf>,
}

#[derive(Debug, Serialize)]
struct BridgeExerciseReport {
    asset: String,
    source_chain_id: u64,
    destination_chain_id: u64,
    actor: Address,
    token_address: Address,
    source_bridge: Address,
    destination_bridge: Address,
    deposit_tx_hash: B256,
    claim_tx_hash: B256,
    deposit_block_number: u64,
    deposit_index: u64,
    deposit_root: B256,
    state_root: B256,
    verification_wait_secs: u64,
    balance_before: String,
    balance_after: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
enum AssetMode {
    Native,
    TokenA,
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();
    tracing_subscriber::fmt().init();

    let command_line_interface = CommandLineInterface::parse();
    let runtime = LoadedRuntime::load(command_line_interface.config)?;

    let source_chain_id =
        command_line_interface.source_chain_id.unwrap_or(default_source_chain_id(&runtime)?);
    let destination_chain_id =
        command_line_interface.destination_chain_id.unwrap_or(runtime.config.base_chain_id);
    let amount = U256::from(command_line_interface.amount_wei);

    if source_chain_id == destination_chain_id {
        bail!("source and destination chains must differ");
    }

    let report = exercise_bridge(
        &runtime,
        source_chain_id,
        destination_chain_id,
        command_line_interface.asset,
        amount,
        Duration::from_secs(command_line_interface.timeout_secs),
    )
    .await?;

    if let Some(json_out) = command_line_interface.json_out {
        if let Some(parent_directory) = json_out.parent() {
            fs::create_dir_all(parent_directory)
                .wrap_err_with(|| format!("failed to create {}", parent_directory.display()))?;
        }
        fs::write(&json_out, serde_json::to_vec_pretty(&report)?)
            .wrap_err_with(|| format!("failed to write {}", json_out.display()))?;
    }

    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
}

async fn exercise_bridge(
    runtime: &LoadedRuntime,
    source_chain_id: u64,
    destination_chain_id: u64,
    asset_mode: AssetMode,
    amount: U256,
    timeout: Duration,
) -> Result<BridgeExerciseReport> {
    let source_chain = runtime.chain(source_chain_id)?;
    let destination_chain = runtime.chain(destination_chain_id)?;
    let source_deploy_addresses = runtime.deployment(source_chain_id)?;
    let destination_deploy_addresses = runtime.deployment(destination_chain_id)?;
    let actor_signer = runtime.owner_signer()?;
    let actor = actor_signer.address();
    let token_address = selected_token_address(
        asset_mode,
        source_deploy_addresses.token_a,
        destination_deploy_addresses.token_a,
    )?;

    let source_signer_provider = signer_provider(source_chain, actor_signer.clone()).await?;
    let source_read_provider = read_provider(source_chain).await?;
    let destination_signer_provider = signer_provider(destination_chain, actor_signer).await?;
    let destination_read_provider = read_provider(destination_chain).await?;
    let chain_manager_client = HttpClientBuilder::default()
        .build(format!("http://{}", runtime.config.services.chain_manager.bind))
        .wrap_err("failed to connect to chain-manager")?;

    if asset_mode == AssetMode::TokenA {
        let source_token =
            IERC20::new(source_deploy_addresses.token_a, source_signer_provider.clone());
        let approval_receipt = source_token
            .approve(source_deploy_addresses.bridge, amount)
            .send()
            .await
            .wrap_err("failed to approve bridge token spend")?
            .get_receipt()
            .await
            .wrap_err("failed waiting for approve receipt")?;
        ensure_successful_receipt("approve bridge token spend", &approval_receipt)?;
    }

    let balance_before =
        read_destination_balance(asset_mode, &destination_read_provider, token_address, actor)
            .await
            .wrap_err("failed to read destination balance before claim")?;

    let destination_bridge =
        IBridge::new(destination_deploy_addresses.bridge, destination_read_provider.clone());
    let destination_bridge_balance = destination_bridge
        .getBalance(token_address)
        .call()
        .await
        .wrap_err("failed to read destination bridge balance")?;
    if destination_bridge_balance < amount {
        if asset_mode == AssetMode::Native {
            let funding_request = TransactionRequest::default()
                .with_to(destination_deploy_addresses.bridge)
                .with_value(amount - destination_bridge_balance);
            let funding_receipt = destination_signer_provider
                .send_transaction(funding_request)
                .await
                .wrap_err("failed to top up destination bridge native balance")?
                .get_receipt()
                .await
                .wrap_err("failed waiting for native bridge top-up receipt")?;
            ensure_successful_receipt("destination bridge native top-up", &funding_receipt)?;
        } else {
            bail!(
                "destination bridge balance {} is below required amount {}",
                destination_bridge_balance,
                amount
            );
        }
    }

    let deposit_params = IBridge::DepositParams {
        amount,
        token: token_address,
        to: actor,
        destinationChain: U256::from(destination_chain_id),
    };
    let deposit_receipt = source_signer_provider
        .send_transaction(
            TransactionRequest::default()
                .with_to(source_deploy_addresses.bridge)
                .input(IBridge::depositCall { depositParams: deposit_params }.abi_encode().into())
                .with_value(if asset_mode == AssetMode::Native { amount } else { U256::ZERO }),
        )
        .await
        .wrap_err("failed to send deposit transaction")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for deposit receipt")?;
    ensure_successful_receipt("deposit transaction", &deposit_receipt)?;
    let deposit_transaction_hash = deposit_receipt.transaction_hash;
    let (deposit_block_number, deposit_record) = parse_deposit_record(
        &deposit_receipt,
        source_chain_id,
        destination_chain_id,
        actor,
        amount,
    )?;

    let header = chain_manager_client
        .finalised_header(source_chain_id, BlockNumberOrTag::Number(deposit_block_number))
        .await
        .wrap_err("failed to fetch finalized source header")?;

    let verification_started = Instant::now();
    wait_for_root_verification(
        &destination_read_provider,
        destination_deploy_addresses.validator_manager,
        source_chain_id,
        deposit_block_number,
        deposit_record.deposit_root,
        header.state_root,
        timeout,
    )
    .await?;

    let source_bridge_reader = IBridge::new(source_deploy_addresses.bridge, source_read_provider);
    let proof = source_bridge_reader
        .getDepositProof(U256::from(deposit_record.deposit_index))
        .call()
        .await
        .wrap_err("failed to fetch deposit proof from source bridge")?;

    let destination_bridge_signer =
        IBridge::new(destination_deploy_addresses.bridge, destination_signer_provider.clone());
    let claim_params = IBridge::ClaimParams {
        depositIndex: U256::from(deposit_record.deposit_index),
        sourceChain: u32::try_from(source_chain_id)
            .map_err(|_| eyre!("source chain id {} exceeds uint32", source_chain_id))?,
        token: token_address,
        to: actor,
        amount,
        sourceRoot: deposit_record.deposit_root,
        blockNumber: U256::from(deposit_block_number),
        stateRoot: header.state_root,
        proof,
    };
    let claim_receipt = destination_bridge_signer
        .claim(claim_params)
        .send()
        .await
        .wrap_err("failed to send claim transaction")?
        .get_receipt()
        .await
        .wrap_err("failed waiting for claim receipt")?;
    ensure_successful_receipt("claim transaction", &claim_receipt)?;
    let claim_transaction_hash = claim_receipt.transaction_hash;

    let balance_after =
        read_destination_balance(asset_mode, &destination_read_provider, token_address, actor)
            .await
            .wrap_err("failed to read destination balance after claim")?;

    let verification_wait_secs = verification_started.elapsed().as_secs();
    info!(
        source_chain_id,
        destination_chain_id,
        actor = %actor,
        deposit_tx_hash = %deposit_transaction_hash,
        claim_tx_hash = %claim_transaction_hash,
        "bridge exercise completed"
    );

    Ok(BridgeExerciseReport {
        asset: asset_mode_label(asset_mode).to_owned(),
        source_chain_id,
        destination_chain_id,
        actor,
        token_address,
        source_bridge: source_deploy_addresses.bridge,
        destination_bridge: destination_deploy_addresses.bridge,
        deposit_tx_hash: deposit_transaction_hash,
        claim_tx_hash: claim_transaction_hash,
        deposit_block_number,
        deposit_index: deposit_record.deposit_index,
        deposit_root: deposit_record.deposit_root,
        state_root: header.state_root,
        verification_wait_secs,
        balance_before: balance_before.to_string(),
        balance_after: balance_after.to_string(),
    })
}

fn selected_token_address(
    asset_mode: AssetMode,
    source_token_address: Address,
    destination_token_address: Address,
) -> Result<Address> {
    match asset_mode {
        AssetMode::Native => Ok(Address::ZERO),
        AssetMode::TokenA => {
            if source_token_address != destination_token_address {
                bail!(
                    "source token {} does not match destination token {}",
                    source_token_address,
                    destination_token_address
                );
            }
            Ok(source_token_address)
        }
    }
}

async fn read_destination_balance(
    asset_mode: AssetMode,
    destination_read_provider: &alloy::providers::DynProvider,
    token_address: Address,
    actor: Address,
) -> Result<U256> {
    match asset_mode {
        AssetMode::Native => destination_read_provider
            .get_balance(actor)
            .await
            .wrap_err("failed to read destination native balance"),
        AssetMode::TokenA => {
            let destination_token = IERC20::new(token_address, destination_read_provider.clone());
            destination_token
                .balanceOf(actor)
                .call()
                .await
                .wrap_err("failed to read destination token balance")
        }
    }
}

fn asset_mode_label(asset_mode: AssetMode) -> &'static str {
    match asset_mode {
        AssetMode::Native => "native",
        AssetMode::TokenA => "token-a",
    }
}

async fn wait_for_root_verification(
    destination_read_provider: &alloy::providers::DynProvider,
    validator_manager_address: Address,
    source_chain_id: u64,
    block_number: u64,
    deposit_root: B256,
    state_root: B256,
    timeout: Duration,
) -> Result<()> {
    let validator_manager =
        IValidatorManager::new(validator_manager_address, destination_read_provider.clone());
    let started = Instant::now();

    loop {
        let root_params = RootParams {
            blockNumber: U256::from(block_number),
            bridgeRoot: deposit_root,
            stateRoot: state_root,
            sourceChainId: U256::from(source_chain_id),
        };

        if validator_manager
            .isRootVerified(root_params)
            .call()
            .await
            .wrap_err("failed to query destination validator manager")?
        {
            return Ok(());
        }

        if started.elapsed() > timeout {
            bail!("timed out waiting for destination root verification");
        }

        sleep(Duration::from_secs(3)).await;
    }
}

fn parse_deposit_record(
    receipt: &alloy::rpc::types::TransactionReceipt,
    expected_source_chain_id: u64,
    expected_destination_chain_id: u64,
    expected_recipient: Address,
    expected_amount: U256,
) -> Result<(u64, DepositEventRecord)> {
    let block_number =
        receipt.block_number.ok_or_else(|| eyre!("deposit receipt missing block number"))?;
    let event = parse_deposit_event(receipt)?;

    if event.amount != expected_amount {
        bail!("deposit amount {} does not match expected {}", event.amount, expected_amount);
    }
    if event.recipient != expected_recipient {
        bail!(
            "deposit recipient {} does not match expected {}",
            event.recipient,
            expected_recipient
        );
    }
    if event.source_chain_id != expected_source_chain_id {
        bail!(
            "deposit source chain {} does not match expected {}",
            event.source_chain_id,
            expected_source_chain_id
        );
    }
    if event.destination_chain_id != expected_destination_chain_id {
        bail!(
            "deposit destination chain {} does not match expected {}",
            event.destination_chain_id,
            expected_destination_chain_id
        );
    }

    Ok((block_number, event))
}

fn default_source_chain_id(runtime: &LoadedRuntime) -> Result<u64> {
    runtime
        .config
        .chains
        .iter()
        .find(|chain_config| chain_config.id != runtime.config.base_chain_id)
        .map(|chain_config| chain_config.id)
        .ok_or_else(|| eyre!("unable to determine a non-base source chain"))
}

fn ensure_successful_receipt(
    action: &str,
    receipt: &alloy::rpc::types::TransactionReceipt,
) -> Result<()> {
    if receipt.status() {
        return Ok(());
    }

    bail!("{} reverted in transaction {}", action, receipt.transaction_hash)
}
