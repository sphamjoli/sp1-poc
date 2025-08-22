-include .env

RUST_TOOLCHAIN ?= nightly-2025-01-30
RUST_EDITION ?= 2021
CHAIN_ID ?= 8453
PROVER_TYPE ?= cpu
TARGET_DIR ?= target
PROGRAM_NAME ?= bridge-program
ELF_PATH ?= $(TARGET_DIR)/elf-compilation/riscv32im-succinct-zkvm-elf/release/$(PROGRAM_NAME)

GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m 

.PHONY: help init install-rust install-taplo install-sp1 setup-submodules \
        install-dependencies fmt lint clippy test clean ci update \
        build-program create-elf create-program-key generate-groth16-proof \
        execute-program validate-env check-tools check-sp1 generate-proof-gpu \
        generate-proof-mock show-structure

.DEFAULT_GOAL := help

help:
	@echo "$(GREEN)SP1 Bridge Project - Available Commands:$(NC)"
	@echo ""
	@echo "$(YELLOW)Setup & Installation:$(NC)"
	@echo "  $(YELLOW)init$(NC)                    - Initialize the entire project"
	@echo "  $(YELLOW)install-rust$(NC)           - Install Rust toolchain"
	@echo "  $(YELLOW)install-taplo$(NC)          - Install TAPLO TOML formatter"
	@echo "  $(YELLOW)install-sp1$(NC)            - Install SP1 toolchain (cargo-prove)"
	@echo "  $(YELLOW)install-dependencies$(NC)   - Fetch Rust dependencies"
	@echo "  $(YELLOW)setup-submodules$(NC)       - Initialize git submodules"
	@echo ""
	@echo "$(YELLOW)Development:$(NC)"
	@echo "  $(YELLOW)fmt$(NC)                    - Format code"
	@echo "  $(YELLOW)lint$(NC)                   - Check code formatting"
	@echo "  $(YELLOW)clippy$(NC)                 - Run Clippy linter"
	@echo "  $(YELLOW)test$(NC)                   - Run tests"
	@echo "  $(YELLOW)ci$(NC)                     - Run CI workflow (lint + clippy + test)"
	@echo ""
	@echo "$(YELLOW)SP1 Operations:$(NC)"
	@echo "  $(YELLOW)build-program$(NC)          - Build SP1 program to ELF"
	@echo "  $(YELLOW)execute-program$(NC)        - Execute program without proving (fast)"
	@echo "  $(YELLOW)create-program-key$(NC)     - Generate program verification key"
	@echo "  $(YELLOW)generate-groth16-proof$(NC) - Generate Groth16 proof"
	@echo "  $(YELLOW)generate-proof-gpu$(NC)     - Generate proof using GPU"
	@echo "  $(YELLOW)generate-proof-mock$(NC)    - Generate mock proof for testing"
	@echo ""
	@echo "$(YELLOW)Maintenance:$(NC)"
	@echo "  $(YELLOW)clean$(NC)                  - Clean build artifacts"
	@echo "  $(YELLOW)update$(NC)                 - Update dependencies and submodules"
	@echo "  $(YELLOW)show-structure$(NC)         - Show project structure"
	@echo ""
	@echo "$(GREEN)Environment Variables:$(NC)"
	@echo "  $(YELLOW)PROGRAM_NAME$(NC)     - Program crate name (default: $(PROGRAM_NAME))"
	@echo "  $(YELLOW)RUST_TOOLCHAIN$(NC)   - Rust toolchain version (default: $(RUST_TOOLCHAIN))"
	@echo "  $(YELLOW)CHAIN_ID$(NC)         - Chain ID for proof generation (default: $(CHAIN_ID))"
	@echo "  $(YELLOW)PROVER_TYPE$(NC)      - Prover type: cpu/gpu/network/mock (default: $(PROVER_TYPE))"
	@echo ""
	@echo "$(GREEN)Example Workflow:$(NC)"
	@echo "  make init                    # Setup project"
	@echo "  make build-program           # Build SP1 program"
	@echo "  make execute-program         # Test execution"
	@echo "  make generate-groth16-proof  # Generate proof"

init: validate-env install-rust install-taplo install-sp1 setup-submodules install-dependencies
	@echo "$(GREEN)✓ Project initialization complete$(NC)"

validate-env:
	@echo "$(YELLOW)Validating environment...$(NC)"
	@command -v git >/dev/null 2>&1 || { echo "$(RED)Error: git is required$(NC)"; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo "$(RED)Error: curl is required$(NC)"; exit 1; }

install-rust:
	@echo "$(YELLOW)Installing Rust toolchain...$(NC)"
	@if ! command -v rustup >/dev/null 2>&1; then \
		echo "Installing rustup..."; \
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; \
		. ~/.cargo/env; \
	fi
	@rustup install $(RUST_TOOLCHAIN)
	@rustup component add rustfmt --toolchain $(RUST_TOOLCHAIN)
	@rustup component add clippy --toolchain $(RUST_TOOLCHAIN)
	@echo "$(GREEN)✓ Rust toolchain installed$(NC)"

install-sp1:
	@echo "$(YELLOW)Installing SP1 toolchain...$(NC)"
	@if ! command -v cargo-prove >/dev/null 2>&1; then \
		echo "Installing SP1 via sp1up..."; \
		curl -L https://sp1.succinct.xyz | bash; \
		. ~/.bashrc || . ~/.zshrc || true; \
		sp1up; \
	fi
	@echo "$(GREEN)✓ SP1 toolchain installed$(NC)"

install-taplo:
	@echo "$(YELLOW)Installing TAPLO...$(NC)"
	@if ! command -v taplo >/dev/null 2>&1; then \
		cargo install taplo-cli --locked; \
	fi
	@echo "$(GREEN)✓ TAPLO installed$(NC)"

setup-submodules:
	@echo "$(YELLOW)Setting up submodules...$(NC)"
	@if [ -d "contracts" ]; then \
		cd contracts && git submodule update --init --recursive; \
	else \
		git submodule update --init --recursive; \
	fi
	@echo "$(GREEN)✓ Submodules initialized$(NC)"

install-dependencies:
	@echo "$(YELLOW)Fetching dependencies...$(NC)"
	@cargo fetch
	@echo "$(GREEN)✓ Dependencies fetched$(NC)"

check-tools:
	@echo "$(YELLOW)Checking required tools...$(NC)"
	@command -v rustup >/dev/null 2>&1 || { echo "$(RED)Error: rustup not found. Run 'make install-rust'$(NC)"; exit 1; }
	@command -v taplo >/dev/null 2>&1 || { echo "$(RED)Error: taplo not found. Run 'make install-taplo'$(NC)"; exit 1; }
	@echo "$(GREEN)✓ All tools available$(NC)"

check-sp1:
	@echo "$(YELLOW)Checking SP1 installation...$(NC)"
	@command -v cargo-prove >/dev/null 2>&1 || { echo "$(RED)Error: cargo-prove not found. Run 'make install-sp1'$(NC)"; exit 1; }
	@echo "$(GREEN)✓ SP1 tools available$(NC)"

fmt: check-tools
	@echo "$(YELLOW)Formatting code...$(NC)"
	@find crates -name "*.rs" -exec rustup run $(RUST_TOOLCHAIN) rustfmt {} --edition $(RUST_EDITION) \; 2>/dev/null || true
	@taplo fmt
	@echo "$(GREEN)✓ Code formatted$(NC)"

lint: check-tools
	@echo "$(YELLOW)Checking code formatting...$(NC)"
	@find crates -name "*.rs" -exec rustup run $(RUST_TOOLCHAIN) rustfmt --check {} --edition $(RUST_EDITION) \; 2>/dev/null || { echo "$(RED)Code formatting check failed$(NC)"; exit 1; }
	@taplo fmt --check || { echo "$(RED)TOML formatting check failed$(NC)"; exit 1; }
	@echo "$(GREEN)✓ Code formatting OK$(NC)"

clippy: check-tools
	@echo "$(YELLOW)Running Clippy...$(NC)"
	@cargo clippy --all-targets --all-features --locked --workspace --quiet -- -D warnings
	@echo "$(GREEN)✓ Clippy checks passed$(NC)"

test:
	@echo "$(YELLOW)Running tests...$(NC)"
	@cargo test --workspace
	@echo "$(GREEN)✓ Tests passed$(NC)"

clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@cargo clean
	@rm -rf $(TARGET_DIR)/
	@echo "$(GREEN)✓ Clean complete$(NC)"

ci: lint clippy test
	@echo "$(GREEN)✓ CI workflow complete$(NC)"

update:
	@echo "$(YELLOW)Updating dependencies...$(NC)"
	@cargo update
	@git submodule update --remote
	@echo "$(GREEN)✓ Update complete$(NC)"

build-program: check-sp1
	@echo "$(YELLOW)Building SP1 program ($(PROGRAM_NAME))...$(NC)"
	@if [ ! -d "crates/$(PROGRAM_NAME)" ]; then \
		echo "$(RED)Error: Program crate 'crates/$(PROGRAM_NAME)' not found$(NC)"; \
		exit 1; \
	fi
	@cd crates/$(PROGRAM_NAME) && cargo prove build
	@echo "$(GREEN)✓ SP1 program built to ELF$(NC)"

execute-program: build-program
	@echo "$(YELLOW)Executing program without proving...$(NC)"
	@cd crates/bridge-script && \
		RUSTFLAGS="-C target-cpu=native" SP1_PROVER=cpu RUST_LOG=info cargo run --bin evm --release -- --chain-id $(CHAIN_ID) --system groth16
	@echo "$(GREEN)✓ Program executed successfully$(NC)"

create-elf: build-program

create-program-key: build-program
	@echo "$(YELLOW)Generating program verification key...$(NC)"
	@if [ ! -f "$(ELF_PATH)" ]; then \
		echo "$(RED)Error: ELF file not found at $(ELF_PATH)$(NC)"; \
		echo "$(YELLOW)Available ELF files:$(NC)"; \
		find $(TARGET_DIR) -name "*.elf" -o -name "*$(PROGRAM_NAME)*" 2>/dev/null || echo "No ELF files found"; \
		exit 1; \
	fi
	@cargo prove vkey --elf $(ELF_PATH)
	@echo "$(GREEN)✓ Program verification key created$(NC)"

generate-groth16-proof: build-program
	@echo "$(YELLOW)Generating Groth16 proof (Chain ID: $(CHAIN_ID), Prover: $(PROVER_TYPE))...$(NC)"
	@cd crates/bridge-script && \
		RUSTFLAGS="-C target-cpu=native" \
		SP1_PROVER=$(PROVER_TYPE) \
		RUST_LOG=info \
		cargo run --bin evm --release -- --chain-id $(CHAIN_ID) --system groth16
	@echo "$(GREEN)✓ Groth16 proof generated$(NC)"

generate-proof-gpu: PROVER_TYPE=gpu
generate-proof-gpu: generate-groth16-proof

generate-proof-mock: PROVER_TYPE=local
generate-proof-mock: generate-groth16-proof

show-structure:
	@echo "$(GREEN)Project Structure:$(NC)"
	@echo "$(YELLOW)Crates:$(NC)"
	@find crates -maxdepth 1 -type d -not -path crates | sed 's|crates/|  - |' | sort
	@echo ""
	@echo "$(YELLOW)Key Files:$(NC)"
	@ls -la | grep -E "(Cargo|Makefile|\.env)" | awk '{print "  - " $$9}'"