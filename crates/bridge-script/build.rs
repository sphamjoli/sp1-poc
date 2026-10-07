use sp1_build::{build_program_with_args, BuildArgs};

fn main() {
    build_program_with_args("../bridge-program", BuildArgs { locked: true, ..Default::default() })
}
