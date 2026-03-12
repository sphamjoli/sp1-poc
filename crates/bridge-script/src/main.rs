use alloy_consensus::Header;
use alloy_primitives::B256;
use alloy_rpc_types::BlockNumberOrTag;
use chain_manager::api::{ChainConfig, ChainManagerClient, ChainManagerImpl};
use clap::{Parser, ValueEnum};
use futures::executor::block_on;
use sp1_db::repository::{
    BridgeConfig, BridgeEvent, BridgeRepository, ClaimEvent, EventRepository, MongoDBRepository,
};
use sp1_sdk::{
    include_elf, CpuProver, Prover, ProverClient, SP1ProofWithPublicValues, SP1Stdin,
    SP1VerifyingKey,
};
use std::{collections::HashMap, env, time::Instant};
pub const BRIDGE_ELF: &[u8] = include_elf!("bridge-program");
pub const MAX_EVENTS_PER_EPOCH: u32 = 1000;

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct EventsWithStateInfo {
    pub events: Vec<BridgeEvent>,
    pub state_root: B256,
    pub parent_hash: B256,
    pub receipts_root: B256,
    pub chain_id: u64,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct ZkVMInput {
    pub bridge_config: BridgeConfig,
    pub new_deposits: Vec<BridgeEvent>,
    pub processed_claims: Vec<ClaimEvent>,
    pub chain_id: u64,
}

#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Ord, ValueEnum, Debug)]
enum ProofSystem {
    Plonk,
    Groth16,
}
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct EVMArgs {
    #[arg(long, value_enum, default_value = "groth16")]
    system: ProofSystem,
}

fn main() {
    if let Err(e) = block_on(run()) {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    sp1_sdk::utils::setup_logger();
    dotenv::dotenv().ok();
    let configs: Vec<ChainConfig> = [
        ChainConfig { rpc_url: "http://localhost:8545".to_string(), chain_id: 31338 },
        ChainConfig { rpc_url: "http://localhost:8546".to_string(), chain_id: 31339 },
    ]
    .to_vec();
    let (_server_handler, http_client) =
        ChainManagerImpl::new(configs.clone()).create_start_server("127.0.0.1:3000").await?;

    let mongodb_url = env::var("MONGO_DB_URL").expect("MONGO_DB_URL must be set");
    let mongo_repository = MongoDBRepository::new(mongodb_url)?;

    let hasura_url = env::var("HASURA_URL").expect("HASURA_URL must be set");
    let hasura_secret = env::var("HASURA_SECRET").expect("HASURA_SECRET must be set");
    let mut repository = BridgeRepository::new(hasura_url, hasura_secret)?;
    let client = ProverClient::builder().cpu().build();
    let (proving_key, verifying_key) = client.setup(BRIDGE_ELF);
    let start_time = Instant::now();
    let mut event_data: Vec<EventsWithStateInfo> = Vec::new();
    let mut successful = 0;
    for config in configs {
        let deposit_events = repository.get_deposit_events(config.chain_id.into())?;
        let unprocessed_events: Vec<BridgeEvent> = deposit_events
            .clone()
            .into_iter()
            .filter(|event| !mongo_repository.event_exists(&event.transaction_hash))
            .collect();

        if unprocessed_events.is_empty() {
            continue;
        }
        successful += unprocessed_events.clone().len();

        // group by chain id
        // for each chain futher group by block number
        // For each group by block number fetch the block state
        // Create a new EventsWithStateInfo struct
        // submit data to SP1 program
        let mut grouped_block: HashMap<String, Vec<BridgeEvent>> = HashMap::new();
        unprocessed_events.clone().into_iter().for_each(|event| {
            grouped_block
                .entry(event.clone().block_number)
                .or_insert_with(Vec::<BridgeEvent>::new)
                .push(event);
        });

        for (block_number, events) in grouped_block {
            let header: Header = http_client
                .finalised_header(
                    u64::from(config.chain_id),
                    BlockNumberOrTag::Number(block_number.parse()?),
                )
                .await?;

            let block_info = EventsWithStateInfo {
                events,
                state_root: header.state_root,
                parent_hash: header.parent_hash,
                receipts_root: header.receipts_root,
                chain_id: config.chain_id.into(),
            };
            event_data.push(block_info);
        }
    }
    for chain_data in event_data {
        match create_proof(&client, &proving_key, &verifying_key, chain_data).await {
            Ok(proof) => println!("proof created {proof:?}"),
            Err(error) => panic!("{}", format!("Error creating proof {error:?}")),
        }
    }

    println!("Processed {} deposits in {:.2}s", successful, start_time.elapsed().as_secs_f64());
    Ok(())
}

async fn create_proof(
    client: &CpuProver,
    proving_key: &sp1_sdk::SP1ProvingKey,
    verifying_key: &SP1VerifyingKey,
    data: EventsWithStateInfo,
) -> Result<SP1ProofWithPublicValues, Box<dyn std::error::Error>> {
    let mut stdin = SP1Stdin::new();
    stdin.write(&data);
    let proof = client.prove(proving_key, &stdin).run().expect("proving failed");

    // Verify proof.
    client.verify(&proof, verifying_key).expect("verification failed");
    Ok(proof)
}
