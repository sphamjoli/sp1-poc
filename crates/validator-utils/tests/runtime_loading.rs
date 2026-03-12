use std::{
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
};
use validator_utils::LoadedRuntime;

static ENVIRONMENT_LOCK: Mutex<()> = Mutex::new(());

const ETHEREUM_CHAIN_ID: u64 = 31338;
const BASE_CHAIN_ID: u64 = 31339;

fn environment_guard() -> MutexGuard<'static, ()> {
    ENVIRONMENT_LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn runtime_config_path() -> PathBuf {
    workspace_root().join("config/runtime.local.json")
}

fn generated_runtime_directory() -> PathBuf {
    workspace_root().join("artifacts/runtime")
}

fn write_generated_runtime_config(file_name: &str, config: &serde_json::Value) -> PathBuf {
    let generated_directory = generated_runtime_directory();
    let generated_config_path = generated_directory.join(file_name);

    std::fs::create_dir_all(&generated_directory)
        .expect("generated runtime directory should be created");
    std::fs::write(
        &generated_config_path,
        serde_json::to_vec_pretty(config).expect("generated config json"),
    )
    .expect("generated runtime config should be written");

    generated_config_path
}

fn remove_generated_runtime_config(config_path: &Path) {
    if config_path.exists() {
        std::fs::remove_file(config_path).expect("generated runtime config should be removed");
    }
}

fn clear_environment_overrides(names: &[&str]) {
    for name in names {
        std::env::remove_var(name);
    }
}

#[test]
fn runtime_loading_reads_catalog_and_deployments() {
    let _guard = environment_guard();
    let runtime = LoadedRuntime::load(runtime_config_path())
        .expect("runtime should load from checked-in config");

    assert_eq!(runtime.config.base_chain_id, BASE_CHAIN_ID);
    assert_eq!(runtime.validator_catalog.validators().len(), 5);
    assert!(runtime.deployments.contains_key(&ETHEREUM_CHAIN_ID));
    assert!(runtime.deployments.contains_key(&BASE_CHAIN_ID));
}

#[test]
fn runtime_loading_applies_environment_overrides() {
    let _guard = environment_guard();
    let environment_names = [
        "HASURA_URL",
        "ANVIL_PORT_31338",
        "ANVIL_PORT_31339",
        "CHAIN_MANAGER_PORT",
        "NODE_MANAGER_PORT",
        "HASURA_EXTERNAL_PORT",
    ];
    clear_environment_overrides(&environment_names);

    std::env::set_var("ANVIL_PORT_31338", "9545");
    std::env::set_var("ANVIL_PORT_31339", "9546");
    std::env::set_var("CHAIN_MANAGER_PORT", "3010");
    std::env::set_var("NODE_MANAGER_PORT", "7011");
    std::env::set_var("HASURA_EXTERNAL_PORT", "8083");

    let runtime = LoadedRuntime::load(runtime_config_path())
        .expect("runtime should load with environment overrides");

    assert_eq!(
        runtime.chain(ETHEREUM_CHAIN_ID).expect("ethereum chain").rpc_url,
        "http://127.0.0.1:9545/"
    );
    assert_eq!(runtime.chain(BASE_CHAIN_ID).expect("base chain").rpc_url, "http://127.0.0.1:9546/");
    assert_eq!(runtime.config.services.chain_manager.bind, "127.0.0.1:3010");
    assert_eq!(runtime.config.services.node_manager.bind, "127.0.0.1:7011");
    assert_eq!(runtime.config.indexer.hasura_url, "http://localhost:8083/v1/graphql");

    clear_environment_overrides(&environment_names);
}

#[test]
fn runtime_loading_resolves_workspace_root_from_generated_config_path() {
    let _guard = environment_guard();
    let mut generated_config: serde_json::Value = serde_json::from_slice(
        &std::fs::read(runtime_config_path()).expect("base config should exist"),
    )
    .expect("base config json should parse");
    generated_config["indexer"]["hasura_url"] =
        serde_json::Value::String("http://localhost:8083/v1/graphql".to_owned());

    let generated_config_path =
        write_generated_runtime_config("runtime.test.generated.json", &generated_config);
    std::env::set_var("HASURA_URL", "http://localhost:8080/v1/graphql");

    let runtime = LoadedRuntime::load(&generated_config_path)
        .expect("runtime should load from generated config path");

    assert_eq!(
        runtime.workspace_root.canonicalize().expect("workspace root canonical path"),
        workspace_root().canonicalize().expect("expected workspace root canonical path")
    );
    assert_eq!(runtime.validator_catalog.validators().len(), 5);
    assert_eq!(runtime.config.indexer.hasura_url, "http://localhost:8080/v1/graphql");

    remove_generated_runtime_config(&generated_config_path);
    std::env::remove_var("HASURA_URL");
}

#[test]
fn generated_runtime_loading_applies_compose_service_overrides() {
    let _guard = environment_guard();
    let generated_config: serde_json::Value = serde_json::from_slice(
        &std::fs::read(runtime_config_path()).expect("base config should exist"),
    )
    .expect("base config json should parse");
    let generated_config_path = write_generated_runtime_config(
        "runtime.compose-overrides.generated.json",
        &generated_config,
    );

    std::env::set_var("RPC_URL_31338", "http://anvil-31338:8545/");
    std::env::set_var("RPC_URL_31339", "http://anvil-31339:8546/");
    std::env::set_var("CHAIN_MANAGER_BIND", "chain-manager:3010");
    std::env::set_var("NODE_MANAGER_BIND", "node-manager:7011");
    std::env::set_var("HASURA_URL", "http://graphql-engine:8080/v1/graphql");

    let runtime = LoadedRuntime::load(&generated_config_path)
        .expect("runtime should load generated config with compose overrides");

    assert_eq!(
        runtime.chain(ETHEREUM_CHAIN_ID).expect("ethereum chain").rpc_url,
        "http://anvil-31338:8545/"
    );
    assert_eq!(
        runtime.chain(BASE_CHAIN_ID).expect("base chain").rpc_url,
        "http://anvil-31339:8546/"
    );
    assert_eq!(runtime.config.services.chain_manager.bind, "chain-manager:3010");
    assert_eq!(runtime.config.services.node_manager.bind, "node-manager:7011");
    assert_eq!(runtime.config.indexer.hasura_url, "http://graphql-engine:8080/v1/graphql");

    remove_generated_runtime_config(&generated_config_path);
    clear_environment_overrides(&[
        "RPC_URL_31338",
        "RPC_URL_31339",
        "CHAIN_MANAGER_BIND",
        "NODE_MANAGER_BIND",
        "HASURA_URL",
    ]);
}

#[test]
fn generated_runtime_prefers_inline_chain_entries_over_chain_directory_defaults() {
    let _guard = environment_guard();
    let mut generated_config: serde_json::Value = serde_json::from_slice(
        &std::fs::read(runtime_config_path()).expect("base config should exist"),
    )
    .expect("base config json should parse");

    generated_config["chains"] = serde_json::json!([
        {
            "id": ETHEREUM_CHAIN_ID,
            "name": "Ethereum",
            "rpc_url": "http://127.0.0.1:9545/"
        },
        {
            "id": BASE_CHAIN_ID,
            "name": "Base",
            "rpc_url": "http://127.0.0.1:9546/"
        }
    ]);

    let generated_config_path =
        write_generated_runtime_config("runtime.inline-chains.generated.json", &generated_config);
    let runtime = LoadedRuntime::load(&generated_config_path)
        .expect("runtime should load generated inline chain entries");

    assert_eq!(
        runtime.chain(ETHEREUM_CHAIN_ID).expect("ethereum chain").rpc_url,
        "http://127.0.0.1:9545/"
    );
    assert_eq!(runtime.chain(BASE_CHAIN_ID).expect("base chain").rpc_url, "http://127.0.0.1:9546/");

    remove_generated_runtime_config(&generated_config_path);
}

#[test]
fn runtime_loading_ignores_empty_owner_private_key_environment_values() {
    let _guard = environment_guard();

    std::env::remove_var("NODE_MANAGER_PRIVATE_KEY");
    std::env::remove_var("OWNER_PRIVATE_KEY");
    std::env::set_var("NETWORK_PRIVATE_KEY", "");

    let runtime = LoadedRuntime::load(runtime_config_path())
        .expect("runtime should fall back to config owner private key");

    assert_eq!(
        runtime.owner_private_key,
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    );

    std::env::remove_var("NETWORK_PRIVATE_KEY");
}
