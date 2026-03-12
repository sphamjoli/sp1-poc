use chain_manager::api::{ChainConfig, ChainManagerImpl};
use clap::Parser;
use eyre::Result;
use serde::Serialize;
use tracing::info;
use validator_utils::{
    state::write_state_file, unix_timestamp, LoadedRuntime, DEFAULT_RUNTIME_CONFIG,
};

#[derive(Debug, Parser)]
#[command(name = "chain-manager")]
#[command(about = "Local chain-manager RPC server")]
struct CommandLineInterface {
    #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG, env = "RUNTIME_CONFIG")]
    config: String,
}

#[derive(Debug, Serialize)]
struct ChainManagerHeartbeat {
    status: &'static str,
    bind: String,
    #[serde(rename = "chainIds")]
    chain_ids: Vec<u64>,
    #[serde(rename = "startedAt")]
    started_at: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();
    tracing_subscriber::fmt().init();

    let command_line_interface = CommandLineInterface::parse();
    let runtime = LoadedRuntime::load(command_line_interface.config)?;
    runtime.ensure_runtime_directories()?;

    let chain_configs: Vec<ChainConfig> = runtime
        .config
        .chains
        .iter()
        .map(|chain_config| ChainConfig {
            chain_id: chain_config.id,
            rpc_url: chain_config.rpc_url.clone(),
        })
        .collect();
    let bind = runtime.config.services.chain_manager.bind.clone();
    let (server_handle, _) = ChainManagerImpl::new(chain_configs.clone())
        .create_start_server(&bind)
        .await
        .map_err(|error| eyre::eyre!(error.to_string()))?;

    write_state_file(
        &runtime,
        "chain-manager.json",
        &ChainManagerHeartbeat {
            status: "ok",
            bind: bind.clone(),
            chain_ids: chain_configs.iter().map(|chain_config| chain_config.chain_id).collect(),
            started_at: unix_timestamp()?,
        },
    )?;

    info!(bind = %bind, "chain-manager listening");
    server_handle.stopped().await;
    Ok(())
}
