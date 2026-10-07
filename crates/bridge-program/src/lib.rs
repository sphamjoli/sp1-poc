//! Deterministic receipt-proof verification and bridge settlement output for the SP1 guest.
//!
//! Modules decode canonical RLP receipts, verify Merkle Patricia inclusion and classify
//! attestation witnesses. Receipt roots and event expectations are supplied by the host;
//! inclusion verification alone does not authenticate those chain anchors.

#![cfg_attr(not(test), no_std)]
extern crate alloc;

pub mod abi;
pub mod comparer;
pub mod events;
pub mod mpt;
pub mod receipt;
pub mod rlp;
