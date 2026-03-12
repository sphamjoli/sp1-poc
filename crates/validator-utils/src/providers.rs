use crate::config::ChainConfig;
use alloy::{
    providers::{DynProvider, Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
};
use eyre::{Context, Result};

pub async fn read_provider(chain_config: &ChainConfig) -> Result<DynProvider> {
    Ok(ProviderBuilder::new()
        .connect_http(chain_config.rpc_url.parse().wrap_err("invalid chain RPC URL")?)
        .erased())
}

pub async fn signer_provider(
    chain_config: &ChainConfig,
    signer: PrivateKeySigner,
) -> Result<DynProvider> {
    Ok(ProviderBuilder::new()
        .wallet(signer)
        .connect_http(chain_config.rpc_url.parse().wrap_err("invalid chain RPC URL")?)
        .erased())
}
