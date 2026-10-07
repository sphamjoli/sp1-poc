//! GraphQL repository and event models for indexed bridge activity.
//!
//! Host validators use this crate to query pending deposits and attestations. Indexed
//! event records identify work to perform; receipt verification supplies the independent
//! event checks before an attestation is submitted.

pub mod repository;
pub mod utils;
