//! HTTP service for collecting configured EVM blocks, receipts and inclusion proofs.
//!
//! The service connects host validators to RPC providers and constructs receipt witnesses
//! for the SP1 guest. RPC data remains a trust input; numbered block lookup does not
//! establish consensus finality.

pub mod api;
