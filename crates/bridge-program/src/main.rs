#![no_main]
sp1_zkvm::entrypoint!(main);

use alloc::vec::Vec;
use bridge_program::comparer;
use sp1_types::ZkvmInput;
use sp1_zkvm::io;

extern crate alloc;

pub fn main() {
    let input: ZkvmInput = io::read();

    let public_values: Vec<u8> =
        comparer::build_public_values(&input).expect("build_public_values failed");

    io::commit_slice(&public_values);
}
