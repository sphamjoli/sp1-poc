use clap::{Parser, Subcommand};
use eyre::Result;
use validator_utils::{
    issue_certificate, sign_attestation, unix_timestamp, Bootstrapper, LoadedRuntime,
    RuntimeStatusReporter, DEFAULT_RUNTIME_CONFIG,
};

#[derive(Debug, Parser)]
#[command(name = "validator-utils")]
#[command(about = "Local validator bootstrap and signing utilities")]
struct CommandLineInterface {
    #[command(subcommand)]
    subcommand: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Bootstrap {
        #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG)]
        config: String,
    },
    Status {
        #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG)]
        config: String,
    },
    SignAttestation {
        #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG)]
        config: String,
        #[arg(long)]
        validator: String,
        #[arg(long)]
        source_chain_id: u64,
        #[arg(long)]
        block_number: u64,
        #[arg(long)]
        bridge_root: alloy::primitives::B256,
        #[arg(long)]
        state_root: alloy::primitives::B256,
        #[arg(long)]
        timestamp: u64,
    },
    IssueCertificate {
        #[arg(long, default_value = DEFAULT_RUNTIME_CONFIG)]
        config: String,
        #[arg(long)]
        validator: alloy::primitives::Address,
        #[arg(long)]
        target_chain_id: u64,
        #[arg(long)]
        issued_at: Option<u64>,
        #[arg(long)]
        expires_at: Option<u64>,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let command_line_interface = CommandLineInterface::parse();

    match command_line_interface.subcommand {
        Command::Bootstrap { config } => {
            let runtime = LoadedRuntime::load(config)?;
            Bootstrapper::new(&runtime).run().await?;
        }
        Command::Status { config } => {
            let runtime = LoadedRuntime::load(config)?;
            let report = RuntimeStatusReporter::new(&runtime).generate().await?;
            println!("{}", serde_json::to_string_pretty(&report)?);
        }
        Command::SignAttestation {
            config,
            validator,
            source_chain_id,
            block_number,
            bridge_root,
            state_root,
            timestamp,
        } => {
            let runtime = LoadedRuntime::load(config)?;
            let validator_record = runtime.validator_catalog.by_name(&validator)?;
            let signed_attestation = sign_attestation(
                validator_record,
                source_chain_id,
                block_number,
                bridge_root,
                state_root,
                timestamp,
            )?;
            println!("{}", serde_json::to_string_pretty(&signed_attestation)?);
        }
        Command::IssueCertificate { config, validator, target_chain_id, issued_at, expires_at } => {
            let runtime = LoadedRuntime::load(config)?;
            let issued_at_timestamp = issued_at.unwrap_or(unix_timestamp()?);
            let expires_at_timestamp = expires_at.unwrap_or(
                issued_at_timestamp + runtime.config.services.node_manager.certificate_ttl_secs,
            );
            let certificate = issue_certificate(
                &runtime.owner_signer()?,
                validator,
                target_chain_id,
                issued_at_timestamp,
                expires_at_timestamp,
            )
            .await?;
            println!("{}", serde_json::to_string_pretty(&certificate)?);
        }
    }

    Ok(())
}
