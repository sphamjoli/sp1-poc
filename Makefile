-include .env

RUST_TOOLCHAIN ?= stable
RUST_EDITION ?= 2021
CHAIN_ID ?= 31339
PROVER_TYPE ?= cpu
TARGET_DIR ?= target
PROGRAM_NAME ?= bridge-program
ELF_PATH ?= $(TARGET_DIR)/elf-compilation/riscv32im-succinct-zkvm-elf/release/$(PROGRAM_NAME)
ANVIL_NO_FORK ?= false

GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m
NPM ?= npm

export ANVIL_PORT_31338
export ANVIL_PORT_31339
export RPC_URL_31338
export RPC_URL_31339
export CHAIN_MANAGER_BIND
export CHAIN_MANAGER_PORT
export NODE_MANAGER_BIND
export NODE_MANAGER_PORT
export UI_BIND
export UI_PORT
export HASURA_URL
export HASURA_EXTERNAL_PORT
export HASURA_SECRET
export HASURA_GRAPHQL_ADMIN_SECRET
export VALIDATOR_POLL_INTERVAL_SECS
export VALIDATOR_MAX_BACKOFF_SECS
export SP1_INTERVAL_SECS
export SP1_VERIFIER_ADDRESS
export STACK_NAME
export REUSE_RUNTIME_CONFIG
export ANVIL_NO_FORK

.PHONY: help init install-rust install-taplo install-sp1 setup-submodules \
        install-dependencies fmt lint clippy test clean ci update \
        build-program create-elf create-program-key generate-groth16-proof \
        execute-program validate-env check-tools check-sp1 generate-proof-gpu \
        generate-proof-mock show-structure \
        kill-anvil test-bridge test-unit test-contracts test-contracts-fuzz \
        contract-scenario live-scenario scenario-slash scenario-jail scenario-recover \
        scenario-jail-recover scenario-jail-no-rewards scenario-unstake-partial \
        scenario-unstake-full scenario-claim-rewards scenario-slashed-exit \
        scenario-distribute-rewards scenario-warp upgrade-live-contracts \
        test-components deploy-local test-e2e test-e2e-json test-live-bridge \
        bridge bridge-report \
        ui-dev ui-test \
        update-chains remove-chains \
        generate-stack-compose start-runtime-agents stop-runtime-agents start-docker-stack stop-docker-stack \
        upgrade-safety-check update-indexer-config verify-indexer-config restart-indexer reset-indexer ensure-indexer-ready \
        update-chains-existing anvil-up-existing deploy-local-existing ensure-indexer-ready-existing \
        check-runtime-deployments docker-up-chains docker-start-supporting-services docker-start-runtime-services docker-redeploy \
        runtime-dirs anvil-up bootstrap-validator-set start-chain-manager start-node-manager \
        start-validators start-sp1 start-local-stack stop-local-stack smoke-runtime ensure-local-stack \
        reset-runtime-state

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
	@echo "  $(YELLOW)generate-proof-mock$(NC)    - Generate local Groth16 proof (SP1_PROVER=local, no network)"
	@echo ""
	@echo "$(YELLOW)Testing:$(NC)"
	@echo "  $(YELLOW)bridge$(NC)                 - Run the full pipeline (unit tests + e2e) — kills stale Anvil first"
	@echo "  $(YELLOW)test-bridge$(NC)            - Run bridge-program unit tests (no SP1 toolchain needed)"
	@echo "  $(YELLOW)test-unit$(NC)              - Run all workspace lib/unit tests"
	@echo "  $(YELLOW)test-contracts$(NC)         - Run Solidity unit tests (contracts/test/unit)"
	@echo "  $(YELLOW)test-contracts-fuzz$(NC)    - Run Solidity fuzz tests (contracts/test/fuzz)"
	@echo "  $(YELLOW)contract-scenario$(NC)      - Run one Solidity scenario test by name: make contract-scenario TEST=<forge-test>"
	@echo "  $(YELLOW)live-scenario$(NC)          - Run the live scenario runner directly: make live-scenario SCENARIO_ARGS='<subcommand ...>'"
	@echo "  $(YELLOW)scenario-slash$(NC)         - Slash a live validator on the running bridge"
	@echo "  $(YELLOW)scenario-jail$(NC)          - Jail a live validator by slashing below minimum stake"
	@echo "  $(YELLOW)scenario-recover$(NC)       - Restake a live validator back to active status"
	@echo "  $(YELLOW)scenario-jail-recover$(NC)  - Jail then recover a live validator in one command"
	@echo "  $(YELLOW)scenario-jail-no-rewards$(NC) - Jail a validator and verify no new rewards are accrued"
	@echo "  $(YELLOW)scenario-unstake-partial$(NC) - Begin and complete a live partial unstake"
	@echo "  $(YELLOW)scenario-unstake-full$(NC)  - Begin and complete a live full unstake"
	@echo "  $(YELLOW)scenario-claim-rewards$(NC) - Claim pending live validator rewards"
	@echo "  $(YELLOW)scenario-slashed-exit$(NC)  - Jail a validator, then exit immediately"
	@echo "  $(YELLOW)scenario-distribute-rewards$(NC) - Trigger owner-side reward distribution if needed"
	@echo "  $(YELLOW)scenario-warp$(NC)          - Advance an Anvil-backed live chain clock"
	@echo "  $(YELLOW)test-components$(NC)        - Run risk-based component tests (Rust + indexer TS)"
	@echo "  $(YELLOW)deploy-local$(NC)           - Start configured Anvil chains and deploy bridge contracts"
	@echo "  $(YELLOW)upgrade-live-contracts$(NC) - Upgrade live bridge proxies in place with current contract code"
	@echo "  $(YELLOW)anvil-up$(NC)               - Reuse or start the configured Anvil chains"
	@echo "  $(YELLOW)test-e2e$(NC)               - Full end-to-end: real chain state (Anvil) + Groth16 mock proof"
	@echo "  $(YELLOW)test-e2e-json$(NC)          - E2E test that writes structured JSON scenario output"
	@echo "  $(YELLOW)test-live-bridge$(NC)       - Use the running validator stack to deposit and claim across chains"
	@echo "  $(YELLOW)bridge-report$(NC)          - Run complete validation and emit timestamped HTML/JSON report"
	@echo "  $(YELLOW)ui-dev$(NC)                 - Start Vue 3 + Tailwind swap UI"
	@echo "  $(YELLOW)ui-test$(NC)                - Run UI unit + e2e tests"
	@echo "  $(YELLOW)kill-anvil$(NC)             - Stop any Anvil instances on ports $(ANVIL_PORT_31338) and $(ANVIL_PORT_31339)"
	@echo "  $(YELLOW)bootstrap-validator-set$(NC) - Fund, register, and stake the dev validators"
	@echo "  $(YELLOW)start-chain-manager$(NC)    - Start the shared chain-manager process"
	@echo "  $(YELLOW)start-node-manager$(NC)     - Start the node-manager HTTP service"
	@echo "  $(YELLOW)start-validators$(NC)       - Start the five validator processes"
	@echo "  $(YELLOW)start-sp1$(NC)              - Start the SP1 proof and finalization loop"
	@echo "  $(YELLOW)start-local-stack$(NC)      - Launch Anvil, deploy, indexer, chain-manager, bootstrap, node-manager, validators, SP1"
	@echo "  $(YELLOW)start-docker-stack$(NC)     - Launch the full Docker stack, bootstrap validators, and run validators/SP1 in compose"
	@echo "  $(YELLOW)stop-local-stack$(NC)       - Stop chain-manager, node-manager, validator, and SP1 processes"
	@echo "  $(YELLOW)stop-runtime-agents$(NC)    - Stop host-managed chain-manager, node-manager, validator, and SP1 processes"
	@echo "  $(YELLOW)stop-docker-stack$(NC)      - Stop the docker-backed stack for the selected STACK_NAME"
	@echo "  $(YELLOW)smoke-runtime$(NC)          - Check runtime heartbeats and node-manager health"
	@echo "  $(YELLOW)update-chains$(NC)          - Sync runtime, UI, and indexer chain metadata from config/chains"
	@echo "  $(YELLOW)remove-chains$(NC)          - Remove chains listed in config/unsupported and resync generated assets"
	@echo ""
	@echo "$(YELLOW)Indexer:$(NC)"
	@echo "  $(YELLOW)update-indexer-config$(NC)  - Rewrite indexer/config.yaml with local Anvil addresses (run after deploy-local)"
	@echo "  $(YELLOW)verify-indexer-config$(NC)  - Fail if indexer/config.yaml is out of sync with contracts/deploy-out"
	@echo "  $(YELLOW)restart-indexer$(NC)        - Restart Envio Docker container and wait 60 s for it to sync"
	@echo "  $(YELLOW)reset-indexer$(NC)          - Recreate the Envio stack with a fresh Postgres volume"
	@echo "  $(YELLOW)ensure-indexer-ready$(NC)   - Poll Hasura until indexer schema/tables are queryable"
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
	@echo "  $(YELLOW)SP1_VERIFIER_ADDRESS$(NC) - Optional override for the deployed SP1 verifier address"
	@echo ""
	@echo "$(GREEN)Example Workflow:$(NC)"
	@echo "  make init                    # Setup project"
	@echo "  make build-program           # Build SP1 program"
	@echo "  make execute-program         # Test execution"
	@echo "  make generate-groth16-proof  # Generate proof"

init: validate-env install-rust install-taplo install-sp1 setup-submodules install-dependencies
	@echo "$(GREEN) Project initialization complete$(NC)"

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
	@rustup toolchain install $(RUST_TOOLCHAIN)
	@rustup component add rustfmt --toolchain $(RUST_TOOLCHAIN)
	@rustup component add clippy --toolchain $(RUST_TOOLCHAIN)
	@echo "$(GREEN) Rust toolchain installed$(NC)"

install-sp1:
	@echo "$(YELLOW)Installing SP1 toolchain...$(NC)"
	@if ! command -v cargo-prove >/dev/null 2>&1; then \
		echo "Installing SP1 via sp1up..."; \
		curl -L https://sp1.succinct.xyz | bash; \
		. ~/.bashrc || . ~/.zshrc || true; \
		sp1up; \
	fi
	@echo "$(GREEN) SP1 toolchain installed$(NC)"

install-taplo:
	@echo "$(YELLOW)Installing TAPLO...$(NC)"
	@if ! command -v taplo >/dev/null 2>&1; then \
		cargo install taplo-cli --locked; \
	fi
	@echo "$(GREEN) TAPLO installed$(NC)"

setup-submodules:
	@echo "$(YELLOW)Setting up submodules...$(NC)"
	@if [ -d "contracts" ]; then \
		cd contracts && git submodule update --init --recursive; \
	else \
		git submodule update --init --recursive; \
	fi
	@echo "$(GREEN) Submodules initialized$(NC)"

install-dependencies:
	@echo "$(YELLOW)Fetching dependencies...$(NC)"
	@cargo fetch
	@echo "$(GREEN) Dependencies fetched$(NC)"

check-tools:
	@echo "$(YELLOW)Checking required tools...$(NC)"
	@command -v rustup >/dev/null 2>&1 || { echo "$(RED)Error: rustup not found. Run 'make install-rust'$(NC)"; exit 1; }
	@command -v taplo >/dev/null 2>&1 || { echo "$(RED)Error: taplo not found. Run 'make install-taplo'$(NC)"; exit 1; }
	@echo "$(GREEN) All tools available$(NC)"

check-sp1:
	@echo "$(YELLOW)Checking SP1 installation...$(NC)"
	@command -v cargo-prove >/dev/null 2>&1 || { echo "$(RED)Error: cargo-prove not found. Run 'make install-sp1'$(NC)"; exit 1; }
	@echo "$(GREEN) SP1 tools available$(NC)"

fmt: check-tools
	@echo "$(YELLOW)Formatting Rust (workspace)...$(NC)"
	@rustup run $(RUST_TOOLCHAIN) cargo fmt --all
	@echo "$(YELLOW)Formatting TOML...$(NC)"
	@taplo fmt
	@echo "$(GREEN) Code formatted$(NC)"

lint: check-tools
	@echo "$(YELLOW)Checking Rust formatting (workspace)...$(NC)"
	@rustup run $(RUST_TOOLCHAIN) cargo fmt --all --check
	@echo "$(YELLOW)Checking TOML formatting...$(NC)"
	@taplo fmt --check || { echo "$(RED)TOML formatting check failed$(NC)"; exit 1; }
	@echo "$(GREEN) Code formatting OK$(NC)"

clippy: check-tools
	@echo "$(YELLOW)Running Clippy...$(NC)"
	@rustup run $(RUST_TOOLCHAIN) cargo clippy --all-targets --all-features --locked --workspace --quiet -- -D warnings
	@echo "$(GREEN) Clippy checks passed$(NC)"

test:
	@echo "$(YELLOW)Running tests...$(NC)"
	@rustup run $(RUST_TOOLCHAIN) cargo test --workspace
	@echo "$(GREEN) Tests passed$(NC)"

clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@cargo clean
	@rm -rf $(TARGET_DIR)/
	@echo "$(GREEN) Clean complete$(NC)"

ci: lint clippy test
	@echo "$(GREEN) CI workflow complete$(NC)"

update:
	@echo "$(YELLOW)Updating dependencies...$(NC)"
	@cargo update
	@git submodule update --remote
	@echo "$(GREEN) Update complete$(NC)"

build-program: check-sp1
	@echo "$(YELLOW)Building SP1 program ($(PROGRAM_NAME))...$(NC)"
	@if [ ! -d "crates/$(PROGRAM_NAME)" ]; then \
		echo "$(RED)Error: Program crate 'crates/$(PROGRAM_NAME)' not found$(NC)"; \
		exit 1; \
	fi
	@if [ -f "$(ELF_PATH)" ] && ! find "crates/$(PROGRAM_NAME)" -type f -newer "$(ELF_PATH)" | grep -q .; then \
		echo "$(GREEN) Reusing existing ELF at $(ELF_PATH)$(NC)"; \
	else \
		cd crates/$(PROGRAM_NAME) && cargo prove build; \
	fi
	@echo "$(GREEN) SP1 program built to ELF$(NC)"

execute-program: build-program
	@echo "$(YELLOW)Executing program without proving...$(NC)"
	@cd crates/bridge-script && \
		RUSTFLAGS="-C target-cpu=native" SP1_PROVER=cpu RUST_LOG=info cargo run --bin evm --release -- --chain-id $(CHAIN_ID) --system groth16
	@echo "$(GREEN) Program executed successfully$(NC)"

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
	@echo "$(GREEN) Program verification key created$(NC)"

generate-groth16-proof: build-program
	@echo "$(YELLOW)Generating Groth16 proof (Chain ID: $(CHAIN_ID), Prover: $(PROVER_TYPE))...$(NC)"
	@cd crates/bridge-script && \
		RUSTFLAGS="-C target-cpu=native" \
		SP1_PROVER=$(PROVER_TYPE) \
		RUST_LOG=info \
		cargo run --bin evm --release -- --chain-id $(CHAIN_ID) --system groth16
	@echo "$(GREEN) Groth16 proof generated$(NC)"

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
	@ls -la | grep -E "(Cargo|Makefile|\.env)" | awk '{print "  - " $$9}'

test-bridge:
	@echo "$(YELLOW)Running bridge-program unit tests...$(NC)"
	@rustup run $(RUST_TOOLCHAIN) cargo test -p bridge-program --tests -- --nocapture
	@echo "$(GREEN) Bridge tests passed$(NC)"

test-unit:
	@echo "$(YELLOW)Running all workspace unit tests...$(NC)"
	@rustup run $(RUST_TOOLCHAIN) cargo test --workspace --lib
	@echo "$(GREEN) Unit tests passed$(NC)"

test-contracts: deploy-local
	@echo "$(YELLOW)Running Solidity unit tests...$(NC)"
	@cargo build -p validator-utils >/dev/null
	@ETH_RPC_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id 31338)"; \
		BASE_RPC_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id 31339)"; \
		cd contracts && \
		ETH_RPC_URL="$$ETH_RPC_URL" \
		BASE_RPC_URL="$$BASE_RPC_URL" \
		forge test --match-path "test/unit/**" -vv
	@echo "$(GREEN) Solidity unit tests passed$(NC)"

test-contracts-fuzz: deploy-local
	@echo "$(YELLOW)Running Solidity fuzz tests...$(NC)"
	@cargo build -p validator-utils >/dev/null
	@ETH_RPC_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id 31338)"; \
		BASE_RPC_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id 31339)"; \
		cd contracts && \
		ETH_RPC_URL="$$ETH_RPC_URL" \
			BASE_RPC_URL="$$BASE_RPC_URL" \
			forge test --match-path "test/fuzz/**" -vv
	@echo "$(GREEN) Solidity fuzz tests passed$(NC)"

contract-scenario:
	@if [ -z "$(TEST)" ]; then \
		echo "$(RED)Error: TEST is required. Example: make contract-scenario TEST=test_FinalizeWithJailedEquivicator_AndRecover$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Running Solidity scenario against configured chain RPCs: $(TEST)$(NC)"
	@cargo build -p validator-utils >/dev/null
	@ETH_RPC_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id 31338)"; \
		BASE_RPC_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id 31339)"; \
		cd contracts && \
		ETH_RPC_URL="$$ETH_RPC_URL" \
		BASE_RPC_URL="$$BASE_RPC_URL" \
		forge test --match-test "$(TEST)" -vv
	@echo "$(GREEN) Scenario completed$(NC)"

live-scenario:
	@if [ -z "$(strip $(SCENARIO_ARGS))" ]; then \
		echo "$(RED)Error: SCENARIO_ARGS is required. Example: make live-scenario SCENARIO_ARGS='slash --validator alice --amount-wei 50000000000000000000'$(NC)"; \
		exit 1; \
	fi
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" $(SCENARIO_ARGS)

scenario-slash:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" slash --validator "$(SCENARIO_VALIDATOR)" --amount-wei "$(SLASH_AMOUNT_WEI)" $(if $(strip $(SCENARIO_FORCE)),--force)

scenario-jail:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" jail --validator "$(SCENARIO_VALIDATOR)" $(if $(strip $(SCENARIO_FORCE)),--force)

scenario-recover:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" recover --validator "$(SCENARIO_VALIDATOR)" $(if $(strip $(RESTAKE_AMOUNT_WEI)),--amount-wei "$(RESTAKE_AMOUNT_WEI)")

scenario-jail-recover:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" jail-recover --validator "$(SCENARIO_VALIDATOR)" $(if $(strip $(RESTAKE_AMOUNT_WEI)),--amount-wei "$(RESTAKE_AMOUNT_WEI)") $(if $(strip $(SCENARIO_FORCE)),--force)

scenario-jail-no-rewards:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" jail-no-rewards --validator "$(SCENARIO_VALIDATOR)" $(if $(strip $(SCENARIO_FORCE)),--force)

scenario-unstake-partial:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" partial-unstake --validator "$(SCENARIO_VALIDATOR)" --fast-forward $(if $(strip $(UNSTAKE_AMOUNT_WEI)),--amount-wei "$(UNSTAKE_AMOUNT_WEI)")

scenario-unstake-full:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" full-unstake --validator "$(SCENARIO_VALIDATOR)" --fast-forward

scenario-claim-rewards:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" claim-rewards --validator "$(SCENARIO_VALIDATOR)"

scenario-slashed-exit:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" slashed-exit --validator "$(SCENARIO_VALIDATOR)" --fast-forward $(if $(strip $(SCENARIO_FORCE)),--force)

scenario-distribute-rewards:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" distribute-rewards

scenario-warp:
	@RUNTIME_CONFIG=$(SCENARIO_RUNTIME_CONFIG) cargo run -q -p bridge-script --bin live-scenarios -- --config "$(SCENARIO_RUNTIME_CONFIG)" warp --seconds "$(SCENARIO_SECONDS)" $(if $(strip $(SCENARIO_CHAIN_ID)),--chain-id "$(SCENARIO_CHAIN_ID)")

test-components:
	@echo "$(YELLOW)Running component tests (chain-manager, sp1-db, indexer TS)...$(NC)"
	@rustup run $(RUST_TOOLCHAIN) cargo test -p chain-manager
	@rustup run $(RUST_TOOLCHAIN) cargo test -p sp1-db
	@cd indexer && $(NPM) run mocha --silent
	@echo "$(GREEN) Component tests passed$(NC)"

ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ANVIL_CODE_SIZE_LIMIT := 999999
REPORT_SCENARIO_JSON ?= artifacts/reports/bridge/latest-scenario.json
LIVE_BRIDGE_REPORT_JSON ?= artifacts/reports/bridge/live-bridge-report.json
SCENARIO_VALIDATOR ?= alice
SCENARIO_FORCE ?=
SLASH_AMOUNT_WEI ?= 50000000000000000000
RESTAKE_AMOUNT_WEI ?=
UNSTAKE_AMOUNT_WEI ?=
SCENARIO_CHAIN_ID ?=
SCENARIO_SECONDS ?= 1
SCENARIO_ARGS ?=
SCENARIO_STACK_NAME ?= $(if $(wildcard artifacts/runtime/docker/runtime.generated.json),docker,$(STACK_NAME))
SCENARIO_RUNTIME_CONFIG ?= $(if $(filter environment command line,$(origin RUNTIME_CONFIG)),$(RUNTIME_CONFIG),artifacts/runtime/$(SCENARIO_STACK_NAME)/runtime.generated.json)
UPGRADE_RUNTIME_CONFIG ?= $(SCENARIO_RUNTIME_CONFIG)
UPGRADE_CHAIN_ID ?=
UPGRADE_REFERENCE_BUILD_INFO_DIR ?= $(CURDIR)/contracts/upgrade-reference/build-info-$(shell date +%Y%m%d%H%M%S)
UPGRADE_REFERENCE_BUILD_INFO_DIR_NAME ?= $(notdir $(UPGRADE_REFERENCE_BUILD_INFO_DIR))
STACK_NAME ?=
STACK_NAME := $(if $(strip $(STACK_NAME)),$(STACK_NAME),local)
RUNTIME_TEMPLATE_CONFIG ?= config/runtime.local.json
RUNTIME_ROOT := artifacts/runtime/$(STACK_NAME)
RUNTIME_CONFIG ?= $(RUNTIME_ROOT)/runtime.generated.json
RUNTIME_STATE_DIR := $(RUNTIME_ROOT)/state
RUNTIME_LOG_DIR := $(RUNTIME_ROOT)/logs
RUNTIME_PID_DIR := $(RUNTIME_ROOT)/pids
ANVIL_STATE_DIR := $(RUNTIME_STATE_DIR)/anvil
CHAIN_MANAGER_PID_FILE := $(RUNTIME_PID_DIR)/chain-manager.pid
NODE_MANAGER_PID_FILE := $(RUNTIME_PID_DIR)/node-manager.pid
SP1_PID_FILE := $(RUNTIME_PID_DIR)/sp1.pid
VALIDATOR_NAMES := alice bob jenifer spha james
RUNTIME_SCREEN_PREFIX := bridge-$(STACK_NAME)
CHAIN_MANAGER_SCREEN_SESSION := $(RUNTIME_SCREEN_PREFIX)-chain-manager
NODE_MANAGER_SCREEN_SESSION := $(RUNTIME_SCREEN_PREFIX)-node-manager
SP1_SCREEN_SESSION := $(RUNTIME_SCREEN_PREFIX)-sp1
COMPOSE_FILE := $(RUNTIME_ROOT)/docker-compose.generated.yaml
COMPOSE_PROJECT_NAME := bridge-stack-$(STACK_NAME)
RUNTIME_MAKE_ARGS := \
	STACK_NAME="$(STACK_NAME)" \
	RUNTIME_TEMPLATE_CONFIG="$(RUNTIME_TEMPLATE_CONFIG)" \
	RUNTIME_CONFIG="$(RUNTIME_CONFIG)" \
	ANVIL_NO_FORK="$(ANVIL_NO_FORK)" \
	ANVIL_PORT_31338="$(ANVIL_PORT_31338)" \
	ANVIL_PORT_31339="$(ANVIL_PORT_31339)" \
	RPC_URL_31338="$(RPC_URL_31338)" \
	RPC_URL_31339="$(RPC_URL_31339)" \
	CHAIN_MANAGER_BIND="$(CHAIN_MANAGER_BIND)" \
	CHAIN_MANAGER_PORT="$(CHAIN_MANAGER_PORT)" \
	NODE_MANAGER_BIND="$(NODE_MANAGER_BIND)" \
	NODE_MANAGER_PORT="$(NODE_MANAGER_PORT)" \
	UI_BIND="$(UI_BIND)" \
	UI_PORT="$(UI_PORT)" \
	HASURA_URL="$(HASURA_URL)" \
	HASURA_EXTERNAL_PORT="$(HASURA_EXTERNAL_PORT)" \
	HASURA_SECRET="$(HASURA_SECRET)" \
	HASURA_GRAPHQL_ADMIN_SECRET="$(HASURA_GRAPHQL_ADMIN_SECRET)" \
	VALIDATOR_POLL_INTERVAL_SECS="$(VALIDATOR_POLL_INTERVAL_SECS)" \
	VALIDATOR_MAX_BACKOFF_SECS="$(VALIDATOR_MAX_BACKOFF_SECS)" \
	SP1_INTERVAL_SECS="$(SP1_INTERVAL_SECS)"

runtime-dirs:
	@mkdir -p $(RUNTIME_STATE_DIR) $(RUNTIME_LOG_DIR) $(RUNTIME_PID_DIR) $(RUNTIME_STATE_DIR)/validators $(ANVIL_STATE_DIR)

render-runtime-config: runtime-dirs
	@if [ "$(REUSE_RUNTIME_CONFIG)" = "1" ] && [ -f "$(RUNTIME_CONFIG)" ]; then \
		echo "$(GREEN) Reusing runtime configuration at $(RUNTIME_CONFIG)$(NC)"; \
	else \
		echo "$(YELLOW)Resolving runtime configuration...$(NC)"; \
		ANVIL_PORT_31338="$(ANVIL_PORT_31338)" \
		ANVIL_PORT_31339="$(ANVIL_PORT_31339)" \
		RPC_URL_31338="$(if $(filter environment command line,$(origin RPC_URL_31338)),$(RPC_URL_31338),)" \
		RPC_URL_31339="$(if $(filter environment command line,$(origin RPC_URL_31339)),$(RPC_URL_31339),)" \
		CHAIN_MANAGER_BIND="$(if $(filter environment command line,$(origin CHAIN_MANAGER_BIND)),$(CHAIN_MANAGER_BIND),)" \
		CHAIN_MANAGER_PORT="$(CHAIN_MANAGER_PORT)" \
		NODE_MANAGER_BIND="$(if $(filter environment command line,$(origin NODE_MANAGER_BIND)),$(NODE_MANAGER_BIND),)" \
		NODE_MANAGER_PORT="$(NODE_MANAGER_PORT)" \
		UI_BIND="$(if $(filter environment command line,$(origin UI_BIND)),$(UI_BIND),)" \
		UI_PORT="$(UI_PORT)" \
		HASURA_URL="$(if $(filter environment command line,$(origin HASURA_URL)),$(HASURA_URL),)" \
		HASURA_EXTERNAL_PORT="$(HASURA_EXTERNAL_PORT)" \
		HASURA_SECRET="$(HASURA_SECRET)" \
		HASURA_GRAPHQL_ADMIN_SECRET="$(HASURA_GRAPHQL_ADMIN_SECRET)" \
		VALIDATOR_POLL_INTERVAL_SECS="$(VALIDATOR_POLL_INTERVAL_SECS)" \
		VALIDATOR_MAX_BACKOFF_SECS="$(VALIDATOR_MAX_BACKOFF_SECS)" \
		SP1_INTERVAL_SECS="$(SP1_INTERVAL_SECS)" \
		RUNTIME_TEMPLATE_CONFIG=$(RUNTIME_TEMPLATE_CONFIG) \
		RUNTIME_CONFIG=$(RUNTIME_CONFIG) \
		$(NPM) run scripts:runtime-config --silent -- render --template $(RUNTIME_TEMPLATE_CONFIG) --output $(RUNTIME_CONFIG); \
	fi

update-chains: render-runtime-config
	@echo "$(YELLOW)Synchronizing configured chains...$(NC)"
	@RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:sync-chains --silent -- update
	@echo "$(GREEN) Chain metadata synchronized$(NC)"

update-chains-existing: runtime-dirs
	@echo "$(YELLOW)Synchronizing configured chains...$(NC)"
	@REUSE_RUNTIME_CONFIG=1 RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:sync-chains --silent -- update
	@echo "$(GREEN) Chain metadata synchronized$(NC)"

remove-chains: render-runtime-config
	@echo "$(YELLOW)Removing unsupported chains...$(NC)"
	@RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:sync-chains --silent -- remove
	@echo "$(GREEN) Unsupported chains removed$(NC)"

generate-stack-compose: render-runtime-config
	@echo "$(YELLOW)Generating stack docker compose file...$(NC)"
	@RUNTIME_CONFIG=$(RUNTIME_CONFIG) ANVIL_NO_FORK=$(ANVIL_NO_FORK) $(NPM) run scripts:generate-stack-compose --silent
	@echo "$(GREEN) Stack compose generated at $(RUNTIME_ROOT)/docker-compose.generated.yaml$(NC)"

generate-stack-compose-existing:
	@echo "$(YELLOW)Generating stack docker compose file from existing runtime config...$(NC)"
	@RUNTIME_CONFIG=$(RUNTIME_CONFIG) ANVIL_NO_FORK=$(ANVIL_NO_FORK) $(NPM) run scripts:generate-stack-compose --silent
	@echo "$(GREEN) Stack compose generated at $(RUNTIME_ROOT)/docker-compose.generated.yaml$(NC)"

anvil-up: render-runtime-config
	@echo "$(YELLOW)Ensuring local Anvil chains are running...$(NC)"
	@CHAIN_IDS="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(RUNTIME_CONFIG) | tr '\n' ' ')"; \
		ANVIL_STATE_INTERVAL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- anvil-state-interval --config $(RUNTIME_CONFIG))"; \
		for chain_id in $$CHAIN_IDS; do \
			chain_rpc_url="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			chain_port="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-port --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			chain_fork_url="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-fork-url --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			if [ "$(ANVIL_NO_FORK)" = "true" ] || [ "$(ANVIL_NO_FORK)" = "1" ]; then \
				chain_fork_url=""; \
			fi; \
			pid_file="$(RUNTIME_PID_DIR)/anvil-$$chain_id.pid"; \
			log_file="$(RUNTIME_LOG_DIR)/anvil-$$chain_id.log"; \
			state_path="$(ANVIL_STATE_DIR)/$$chain_id"; \
			if [ -f "$$pid_file" ] && kill -0 "$$(cat "$$pid_file")" 2>/dev/null; then \
				echo "$(GREEN) Reusing configured Anvil chain $$chain_id on port $$chain_port$(NC)"; \
			elif lsof -nP -iTCP:"$$chain_port" -sTCP:LISTEN 2>/dev/null | grep -q '[a]nvil'; then \
				echo "$(GREEN) Reusing reachable Anvil chain $$chain_id on port $$chain_port$(NC)"; \
			elif [ "$$(cast chain-id --rpc-url "$$chain_rpc_url" 2>/dev/null || true)" = "$$chain_id" ]; then \
				echo "$(GREEN) Reusing healthy RPC chain $$chain_id on $$chain_rpc_url$(NC)"; \
			elif lsof -nP -iTCP:"$$chain_port" -sTCP:LISTEN >/dev/null 2>&1; then \
				echo "$(YELLOW) Port $$chain_port is in use (may be Docker Anvil). Waiting for RPC...$(NC)"; \
				retries=0; \
				until [ "$$(cast chain-id --rpc-url "$$chain_rpc_url" 2>/dev/null || true)" = "$$chain_id" ]; do \
					retries=$$((retries + 1)); \
					if [ $$retries -ge 60 ]; then \
						echo "$(RED) Port $$chain_port is in use by a non-Anvil process. Re-render runtime config or override the chain rpc_url in config/chains/$$chain_id/chain.json.$(NC)"; \
						exit 1; \
					fi; \
					sleep 2; \
				done; \
				echo "$(GREEN) Reusing Docker Anvil chain $$chain_id on port $$chain_port$(NC)"; \
			else \
				echo "$(YELLOW) Starting Anvil chain $$chain_id on port $$chain_port$(NC)"; \
				mkdir -p "$$state_path"; \
				if [ -n "$$chain_fork_url" ]; then \
					nohup anvil --port "$$chain_port" --chain-id "$$chain_id" --code-size-limit $(ANVIL_CODE_SIZE_LIMIT) --silent --fork-url "$$chain_fork_url" --state "$$state_path" --state-interval "$$ANVIL_STATE_INTERVAL" > "$$log_file" 2>&1 & echo $$! > "$$pid_file"; \
				else \
					nohup anvil --port "$$chain_port" --chain-id "$$chain_id" --code-size-limit $(ANVIL_CODE_SIZE_LIMIT) --silent --state "$$state_path" --state-interval "$$ANVIL_STATE_INTERVAL" > "$$log_file" 2>&1 & echo $$! > "$$pid_file"; \
				fi; \
			fi; \
		done
	@echo "$(YELLOW)Waiting for all Anvil chains to be ready...$(NC)"; \
	CHAIN_IDS="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(RUNTIME_CONFIG) | tr '\n' ' ')"; \
	for chain_id in $$CHAIN_IDS; do \
		chain_rpc_url="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
		echo "  Waiting for chain $$chain_id at $$chain_rpc_url..."; \
		retries=0; \
		until cast chain-id --rpc-url "$$chain_rpc_url" >/dev/null 2>&1; do \
			retries=$$((retries + 1)); \
			if [ $$retries -ge 60 ]; then \
				echo "$(RED) Timed out waiting for chain $$chain_id$(NC)"; \
				exit 1; \
			fi; \
			sleep 2; \
		done; \
		echo "$(GREEN)  Chain $$chain_id is ready$(NC)"; \
	done

anvil-up-existing: runtime-dirs
	@echo "$(YELLOW)Ensuring local Anvil chains are running...$(NC)"
	@CHAIN_IDS="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(RUNTIME_CONFIG) | tr '\n' ' ')"; \
		ANVIL_STATE_INTERVAL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- anvil-state-interval --config $(RUNTIME_CONFIG))"; \
		for chain_id in $$CHAIN_IDS; do \
			chain_rpc_url="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			chain_port="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-port --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			chain_fork_url="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-fork-url --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			if [ "$(ANVIL_NO_FORK)" = "true" ] || [ "$(ANVIL_NO_FORK)" = "1" ]; then \
				chain_fork_url=""; \
			fi; \
			pid_file="$(RUNTIME_PID_DIR)/anvil-$$chain_id.pid"; \
			log_file="$(RUNTIME_LOG_DIR)/anvil-$$chain_id.log"; \
			state_path="$(ANVIL_STATE_DIR)/$$chain_id"; \
			if [ -f "$$pid_file" ] && kill -0 "$$(cat "$$pid_file")" 2>/dev/null; then \
				echo "$(GREEN) Reusing configured Anvil chain $$chain_id on port $$chain_port$(NC)"; \
			elif lsof -nP -iTCP:"$$chain_port" -sTCP:LISTEN 2>/dev/null | grep -q '[a]nvil'; then \
				echo "$(GREEN) Reusing reachable Anvil chain $$chain_id on port $$chain_port$(NC)"; \
			elif [ "$$(cast chain-id --rpc-url "$$chain_rpc_url" 2>/dev/null || true)" = "$$chain_id" ]; then \
				echo "$(GREEN) Reusing healthy RPC chain $$chain_id on $$chain_rpc_url$(NC)"; \
			elif lsof -nP -iTCP:"$$chain_port" -sTCP:LISTEN >/dev/null 2>&1; then \
				echo "$(YELLOW) Port $$chain_port is in use (may be Docker Anvil). Waiting for RPC...$(NC)"; \
				retries=0; \
				until [ "$$(cast chain-id --rpc-url "$$chain_rpc_url" 2>/dev/null || true)" = "$$chain_id" ]; do \
					retries=$$((retries + 1)); \
					if [ $$retries -ge 60 ]; then \
						echo "$(RED) Port $$chain_port is in use by a non-Anvil process. Re-render runtime config or override the chain rpc_url in config/chains/$$chain_id/chain.json.$(NC)"; \
						exit 1; \
					fi; \
					sleep 2; \
				done; \
				echo "$(GREEN) Reusing Docker Anvil chain $$chain_id on port $$chain_port$(NC)"; \
			else \
				echo "$(YELLOW) Starting Anvil chain $$chain_id on port $$chain_port$(NC)"; \
				mkdir -p "$$state_path"; \
				if [ -n "$$chain_fork_url" ]; then \
					nohup anvil --port "$$chain_port" --chain-id "$$chain_id" --code-size-limit $(ANVIL_CODE_SIZE_LIMIT) --silent --fork-url "$$chain_fork_url" --state "$$state_path" --state-interval "$$ANVIL_STATE_INTERVAL" > "$$log_file" 2>&1 & echo $$! > "$$pid_file"; \
				else \
					nohup anvil --port "$$chain_port" --chain-id "$$chain_id" --code-size-limit $(ANVIL_CODE_SIZE_LIMIT) --silent --state "$$state_path" --state-interval "$$ANVIL_STATE_INTERVAL" > "$$log_file" 2>&1 & echo $$! > "$$pid_file"; \
				fi; \
			fi; \
		done
	@echo "$(YELLOW)Waiting for all Anvil chains to be ready...$(NC)"; \
	CHAIN_IDS="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(RUNTIME_CONFIG) | tr '\n' ' ')"; \
	for chain_id in $$CHAIN_IDS; do \
		chain_rpc_url="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
		echo "  Waiting for chain $$chain_id at $$chain_rpc_url..."; \
		retries=0; \
		until cast chain-id --rpc-url "$$chain_rpc_url" >/dev/null 2>&1; do \
			retries=$$((retries + 1)); \
			if [ $$retries -ge 60 ]; then \
				echo "$(RED) Timed out waiting for chain $$chain_id$(NC)"; \
				exit 1; \
			fi; \
			sleep 2; \
		done; \
		echo "$(GREEN)  Chain $$chain_id is ready$(NC)"; \
	done

deploy-local: anvil-up build-program
	@echo "$(YELLOW)Building contracts...$(NC)"
	@cd contracts && forge clean && forge build --quiet
	@PROGRAM_VKEY=$$(cargo prove vkey --elf $(ELF_PATH) | tail -n 1); \
		DEPLOYER_PRIVATE_KEY=$$(node --input-type=module -e "import { randomBytes } from 'node:crypto'; process.stdout.write('0x' + randomBytes(32).toString('hex'))"); \
		RUNTIME_CONFIG_ABS="$$(pwd)/$(RUNTIME_CONFIG)"; \
		DEPLOYMENTS_DIR_ABS="$$(cd "$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- deployments-dir --config $(RUNTIME_CONFIG))" 2>/dev/null && pwd || true)"; \
		if [ -z "$$DEPLOYMENTS_DIR_ABS" ]; then \
			DEPLOYMENTS_DIR_RELATIVE="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- deployments-dir --config $(RUNTIME_CONFIG))"; \
			DEPLOYMENTS_DIR_ABS="$$(pwd)/$$DEPLOYMENTS_DIR_RELATIVE"; \
		fi; \
		CHAIN_IDS="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(RUNTIME_CONFIG) | tr '\n' ' ')"; \
		echo "$(YELLOW)Using PROGRAM_VKEY=$$PROGRAM_VKEY$(NC)"; \
		echo "$(YELLOW)Using DEPLOYER_PRIVATE_KEY derived for deterministic cross-chain addresses$(NC)"; \
		for chain_id in $$CHAIN_IDS; do \
			chain_rpc_url="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			echo "$(YELLOW)Deploying bridge stack on chain $$chain_id (rpc=$$chain_rpc_url)...$(NC)"; \
			( \
				cd contracts && \
				NETWORK_PRIVATE_KEY=$(ANVIL_KEY) DEPLOYER_PRIVATE_KEY=$$DEPLOYER_PRIVATE_KEY PROGRAM_VKEY=$$PROGRAM_VKEY \
				node --import tsx scripts/deploy-local.ts \
				--chain-id "$$chain_id" \
				--rpc-url "$$chain_rpc_url" \
				--runtime-config "$$RUNTIME_CONFIG_ABS" \
				--deployments-dir "$$DEPLOYMENTS_DIR_ABS" \
			); \
		done
	@$(MAKE) --no-print-directory update-chains
	@echo "$(GREEN) Contracts deployed to local Anvil chains$(NC)"

deploy-local-existing: anvil-up-existing build-program
	@echo "$(YELLOW)Building contracts...$(NC)"
	@cd contracts && forge clean && forge build --quiet
	@PROGRAM_VKEY=$$(cargo prove vkey --elf $(ELF_PATH) | tail -n 1); \
		DEPLOYER_PRIVATE_KEY=$$(node --input-type=module -e "import { randomBytes } from 'node:crypto'; process.stdout.write('0x' + randomBytes(32).toString('hex'))"); \
		RUNTIME_CONFIG_ABS="$$(pwd)/$(RUNTIME_CONFIG)"; \
		DEPLOYMENTS_DIR_ABS="$$(cd "$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- deployments-dir --config $(RUNTIME_CONFIG))" 2>/dev/null && pwd || true)"; \
		if [ -z "$$DEPLOYMENTS_DIR_ABS" ]; then \
			DEPLOYMENTS_DIR_RELATIVE="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- deployments-dir --config $(RUNTIME_CONFIG))"; \
			DEPLOYMENTS_DIR_ABS="$$(pwd)/$$DEPLOYMENTS_DIR_RELATIVE"; \
		fi; \
		CHAIN_IDS="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(RUNTIME_CONFIG) | tr '\n' ' ')"; \
		echo "$(YELLOW)Using PROGRAM_VKEY=$$PROGRAM_VKEY$(NC)"; \
		echo "$(YELLOW)Using DEPLOYER_PRIVATE_KEY derived for deterministic cross-chain addresses$(NC)"; \
		for chain_id in $$CHAIN_IDS; do \
			chain_rpc_url="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			echo "$(YELLOW)Deploying bridge stack on chain $$chain_id (rpc=$$chain_rpc_url)...$(NC)"; \
			( \
				cd contracts && \
				NETWORK_PRIVATE_KEY=$(ANVIL_KEY) DEPLOYER_PRIVATE_KEY=$$DEPLOYER_PRIVATE_KEY PROGRAM_VKEY=$$PROGRAM_VKEY \
				node --import tsx scripts/deploy-local.ts \
				--chain-id "$$chain_id" \
				--rpc-url "$$chain_rpc_url" \
				--runtime-config "$$RUNTIME_CONFIG_ABS" \
				--deployments-dir "$$DEPLOYMENTS_DIR_ABS" \
			); \
		done
	@$(MAKE) --no-print-directory update-chains-existing
	@echo "$(GREEN) Contracts deployed to local Anvil chains$(NC)"

upgrade-live-contracts:
	@echo "$(YELLOW)Snapshotting current build-info to $(UPGRADE_REFERENCE_BUILD_INFO_DIR)...$(NC)"
	@if [ ! -d "contracts/out/build-info" ] || [ -z "$$(find contracts/out/build-info -maxdepth 1 -type f -print -quit)" ]; then \
		echo "$(RED)Error: contracts/out/build-info is empty. Compile the currently deployed contracts before upgrading so storage layout can be validated.$(NC)"; \
		exit 1; \
	fi
	@mkdir -p "$(UPGRADE_REFERENCE_BUILD_INFO_DIR)"
	@cp -R contracts/out/build-info/. "$(UPGRADE_REFERENCE_BUILD_INFO_DIR)"
	@echo "$(YELLOW)Building upgraded contract implementations...$(NC)"
	@cd contracts && forge build --quiet
	@CHAIN_IDS="$$(if [ -n "$(strip $(UPGRADE_CHAIN_ID))" ]; then echo "$(UPGRADE_CHAIN_ID)"; else RUNTIME_CONFIG=$(UPGRADE_RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(UPGRADE_RUNTIME_CONFIG) | tr '\n' ' '; fi)"; \
		for chain_id in $$CHAIN_IDS; do \
			chain_rpc_url="$$(RUNTIME_CONFIG=$(UPGRADE_RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(UPGRADE_RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			deployment_file="$$(RUNTIME_CONFIG=$(UPGRADE_RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- deployment-file --config $(UPGRADE_RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			echo "$(YELLOW)Upgrading chain $$chain_id (rpc=$$chain_rpc_url)...$(NC)"; \
			( \
				cd contracts && \
				NETWORK_PRIVATE_KEY=$(ANVIL_KEY) \
				REFERENCE_BUILD_INFO_DIR="$(UPGRADE_REFERENCE_BUILD_INFO_DIR)" \
				REFERENCE_BUILD_INFO_DIR_NAME="$(UPGRADE_REFERENCE_BUILD_INFO_DIR_NAME)" \
				node --import tsx scripts/upgrade-local.ts \
					--chain-id "$$chain_id" \
					--rpc-url "$$chain_rpc_url" \
					--deployment-file "$$deployment_file" \
			); \
		done
	@echo "$(GREEN) Live bridge contracts upgraded in place$(NC)"

bootstrap-validator-set: render-runtime-config
	@echo "$(YELLOW)Bootstrapping validator set...$(NC)"
	@cargo run -p validator-utils -- bootstrap --config $(RUNTIME_CONFIG)
	@echo "$(GREEN) Validator set bootstrapped$(NC)"

build-runtime-binaries:
	@echo "$(YELLOW)Building runtime binaries...$(NC)"
	@cargo build -p chain-manager -p node-manager -p bridge-validator -p bridge-script
	@echo "$(GREEN) Runtime binaries built$(NC)"

start-chain-manager: render-runtime-config build-runtime-binaries _start-chain-manager

_start-chain-manager:
	@echo "$(YELLOW)Starting chain-manager...$(NC)"
	@if screen -ls | grep -q "[.]$(CHAIN_MANAGER_SCREEN_SESSION)[[:space:]]"; then \
		echo "$(GREEN) chain-manager already running$(NC)"; \
	else \
		screen -dmS $(CHAIN_MANAGER_SCREEN_SESSION) zsh -lc 'cd "$(CURDIR)" && exec target/debug/chain-manager --config "$(CURDIR)/$(RUNTIME_CONFIG)" >> "$(CURDIR)/$(RUNTIME_LOG_DIR)/chain-manager.log" 2>&1'; \
		echo "$(GREEN) chain-manager started$(NC)"; \
	fi

start-node-manager: render-runtime-config build-runtime-binaries _start-node-manager

_start-node-manager:
	@echo "$(YELLOW)Starting node-manager...$(NC)"
	@if screen -ls | grep -q "[.]$(NODE_MANAGER_SCREEN_SESSION)[[:space:]]"; then \
		echo "$(GREEN) node-manager already running$(NC)"; \
	else \
		screen -dmS $(NODE_MANAGER_SCREEN_SESSION) zsh -lc 'cd "$(CURDIR)" && exec target/debug/node-manager --config "$(CURDIR)/$(RUNTIME_CONFIG)" >> "$(CURDIR)/$(RUNTIME_LOG_DIR)/node-manager.log" 2>&1'; \
		echo "$(GREEN) node-manager started$(NC)"; \
	fi

start-validators: render-runtime-config build-runtime-binaries _start-validators

_start-validators:
	@echo "$(YELLOW)Starting validator processes...$(NC)"
	@for validator in $(VALIDATOR_NAMES); do \
		session_name="$(RUNTIME_SCREEN_PREFIX)-validator-$$validator"; \
		if screen -ls | grep -q "[.]$$session_name[[:space:]]"; then \
			echo "$(GREEN) validator $$validator already running$(NC)"; \
		else \
			VALIDATOR_NAME="$$validator" screen -dmS "$$session_name" zsh -lc 'cd "$(CURDIR)" && exec target/debug/bridge-validator --config "$(CURDIR)/$(RUNTIME_CONFIG)" --validator "$$VALIDATOR_NAME" >> "$(CURDIR)/$(RUNTIME_LOG_DIR)/validator-$$VALIDATOR_NAME.log" 2>&1'; \
			echo "$(GREEN) validator $$validator started$(NC)"; \
		fi; \
	done

start-sp1: render-runtime-config build-runtime-binaries _start-sp1

_start-sp1:
	@echo "$(YELLOW)Starting SP1 loop...$(NC)"
	@if screen -ls | grep -q "[.]$(SP1_SCREEN_SESSION)[[:space:]]"; then \
		echo "$(GREEN) SP1 loop already running$(NC)"; \
	else \
		screen -dmS $(SP1_SCREEN_SESSION) zsh -lc 'cd "$(CURDIR)" && exec env SP1_PROVER=mock target/debug/evm --config "$(CURDIR)/$(RUNTIME_CONFIG)" --loop --interval-secs 60 >> "$(CURDIR)/$(RUNTIME_LOG_DIR)/sp1.log" 2>&1'; \
		echo "$(GREEN) SP1 loop started$(NC)"; \
	fi

start-runtime-agents: render-runtime-config runtime-dirs build-runtime-binaries
	@command -v screen >/dev/null 2>&1 || { echo "$(RED)screen is required to keep runtime agents detached$(NC)"; exit 1; }
	@$(MAKE) $(RUNTIME_MAKE_ARGS) --no-print-directory _start-chain-manager
	@$(MAKE) $(RUNTIME_MAKE_ARGS) --no-print-directory bootstrap-validator-set
	@$(MAKE) $(RUNTIME_MAKE_ARGS) --no-print-directory _start-node-manager
	@echo "$(YELLOW)Waiting for node-manager health...$(NC)"
	@NODE_MANAGER_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- service-url --config $(RUNTIME_CONFIG) --service node_manager)"; \
		until curl -fsS "$$NODE_MANAGER_URL/healthz" >/dev/null 2>&1; do sleep 2; done
	@$(MAKE) $(RUNTIME_MAKE_ARGS) --no-print-directory _start-validators
	@$(MAKE) $(RUNTIME_MAKE_ARGS) --no-print-directory _start-sp1
	@echo "$(GREEN) Runtime agents are running$(NC)"

start-local-stack: deploy-local reset-indexer ensure-indexer-ready build-runtime-binaries
	@$(MAKE) $(RUNTIME_MAKE_ARGS) --no-print-directory start-runtime-agents
	@echo "$(GREEN) Local validator stack is running$(NC)"

check-runtime-deployments: runtime-dirs
	@RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:check-runtime-deployments --silent -- --config $(RUNTIME_CONFIG)

docker-up-chains:
	@CHAIN_SERVICES="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(RUNTIME_CONFIG) | awk '{printf " anvil-%s", $$1}')"; \
		docker compose -f "$(COMPOSE_FILE)" -p "$(COMPOSE_PROJECT_NAME)" up -d --build $$CHAIN_SERVICES

docker-start-supporting-services:
	@docker compose -f "$(COMPOSE_FILE)" -p "$(COMPOSE_PROJECT_NAME)" up -d --build envio-postgres graphql-engine envio-indexer ui
	@$(MAKE) --no-print-directory ensure-indexer-ready-existing

docker-start-runtime-services:
	@VALIDATOR_SERVICES="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- validator-names --config $(RUNTIME_CONFIG) | awk '{printf " validator-%s", $$1}')"; \
		docker compose -f "$(COMPOSE_FILE)" -p "$(COMPOSE_PROJECT_NAME)" build validator-set-bootstrap chain-manager node-manager sp1 $$VALIDATOR_SERVICES; \
		docker compose -f "$(COMPOSE_FILE)" -p "$(COMPOSE_PROJECT_NAME)" run --rm validator-set-bootstrap; \
		docker compose -f "$(COMPOSE_FILE)" -p "$(COMPOSE_PROJECT_NAME)" up -d chain-manager node-manager sp1 $$VALIDATOR_SERVICES
	@echo "$(YELLOW)Waiting for node-manager health...$(NC)"
	@NODE_MANAGER_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- service-url --config $(RUNTIME_CONFIG) --service node_manager)"; \
		until curl -fsS "$$NODE_MANAGER_URL/healthz" >/dev/null 2>&1; do sleep 2; done

docker-redeploy: stop-runtime-agents
	@echo "$(YELLOW)Rebuilding docker-backed stack $(STACK_NAME) from clean Anvil state...$(NC)"
	@if [ -f "$(COMPOSE_FILE)" ]; then \
			docker compose -f "$(COMPOSE_FILE)" -p "$(COMPOSE_PROJECT_NAME)" down --remove-orphans -v; \
		fi
	@rm -rf "$(RUNTIME_ROOT)/state/anvil" "$(RUNTIME_ROOT)/deployments"
	@$(MAKE) --no-print-directory reset-runtime-state
	@$(MAKE) --no-print-directory generate-stack-compose-existing
	@$(MAKE) --no-print-directory docker-up-chains
	@$(MAKE) --no-print-directory deploy-local-existing
	@$(MAKE) --no-print-directory generate-stack-compose-existing
	@$(MAKE) --no-print-directory docker-start-supporting-services

start-docker-stack:
	@$(MAKE) --no-print-directory generate-stack-compose
	@echo "$(YELLOW)Starting docker-backed stack $(STACK_NAME)...$(NC)"
	@$(MAKE) --no-print-directory docker-up-chains
	@if $(MAKE) --no-print-directory check-runtime-deployments >/dev/null 2>&1; then \
		echo "$(GREEN) Reusing existing deployments and indexer state$(NC)"; \
		$(MAKE) --no-print-directory generate-stack-compose-existing; \
		$(MAKE) --no-print-directory docker-start-supporting-services; \
	else \
		echo "$(YELLOW) Anvil state changed or deployments are missing; performing full redeploy$(NC)"; \
		$(MAKE) --no-print-directory docker-redeploy; \
	fi
	@$(MAKE) --no-print-directory stop-runtime-agents
	@$(MAKE) --no-print-directory docker-start-runtime-services
	@echo "$(GREEN) Docker-backed stack $(STACK_NAME) is running$(NC)"

stop-runtime-agents:
	@echo "$(YELLOW)Stopping local runtime processes...$(NC)"
	@screen -S $(CHAIN_MANAGER_SCREEN_SESSION) -X quit >/dev/null 2>&1 || true
	@screen -S $(NODE_MANAGER_SCREEN_SESSION) -X quit >/dev/null 2>&1 || true
	@screen -S $(SP1_SCREEN_SESSION) -X quit >/dev/null 2>&1 || true
	@for validator in $(VALIDATOR_NAMES); do \
		screen -S "$(RUNTIME_SCREEN_PREFIX)-validator-$$validator" -X quit >/dev/null 2>&1 || true; \
	done
	@for pid_file in $(CHAIN_MANAGER_PID_FILE) $(NODE_MANAGER_PID_FILE) $(SP1_PID_FILE) $(RUNTIME_PID_DIR)/validator-*.pid; do \
		if [ -f "$$pid_file" ]; then \
			kill "$$(cat "$$pid_file")" 2>/dev/null || true; \
			rm -f "$$pid_file"; \
		fi; \
	done
	@pkill -f "target/debug/chain-manager --config $(RUNTIME_CONFIG)" 2>/dev/null || true
	@pkill -f "target/debug/node-manager --config $(RUNTIME_CONFIG)" 2>/dev/null || true
	@pkill -f "target/debug/bridge-validator --config $(RUNTIME_CONFIG)" 2>/dev/null || true
	@pkill -f "target/debug/evm --config $(RUNTIME_CONFIG) --loop" 2>/dev/null || true
	@pkill -f "cargo run -p chain-manager -- --config $(RUNTIME_CONFIG)" 2>/dev/null || true
	@pkill -f "cargo run -p node-manager -- --config $(RUNTIME_CONFIG)" 2>/dev/null || true
	@pkill -f "cargo run -p bridge-validator -- --config $(RUNTIME_CONFIG)" 2>/dev/null || true
	@pkill -f "cargo run -p bridge-script --bin evm -- --config $(RUNTIME_CONFIG) --loop" 2>/dev/null || true
	@echo "$(GREEN) Local runtime processes stopped$(NC)"

stop-local-stack: stop-runtime-agents

stop-docker-stack: stop-runtime-agents
	@echo "$(YELLOW)Stopping docker-backed stack $(STACK_NAME)...$(NC)"
	@if [ -f "$(COMPOSE_FILE)" ]; then \
			docker compose -f "$(COMPOSE_FILE)" -p "$(COMPOSE_PROJECT_NAME)" down --remove-orphans -v; \
		fi
	@rm -rf "$(RUNTIME_ROOT)/state/anvil" "$(RUNTIME_ROOT)/deployments"
	@$(MAKE) --no-print-directory reset-runtime-state
	@echo "$(GREEN) Docker-backed stack $(STACK_NAME) stopped$(NC)"

smoke-runtime:
	@echo "$(YELLOW)Checking runtime health...$(NC)"
	@test -f $(RUNTIME_STATE_DIR)/chain-manager.json
	@test -f $(RUNTIME_STATE_DIR)/node-manager.json
	@test -f $(RUNTIME_STATE_DIR)/sp1.json
	@screen -ls | grep -q "[.]$(CHAIN_MANAGER_SCREEN_SESSION)[[:space:]]"
	@screen -ls | grep -q "[.]$(NODE_MANAGER_SCREEN_SESSION)[[:space:]]"
	@screen -ls | grep -q "[.]$(SP1_SCREEN_SESSION)[[:space:]]"
	@for validator in $(VALIDATOR_NAMES); do \
		test -f $(RUNTIME_STATE_DIR)/validators/$$validator.json; \
		screen -ls | grep -q "[.]$(RUNTIME_SCREEN_PREFIX)-validator-$$validator[[:space:]]"; \
	done
	@NODE_MANAGER_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- service-url --config $(RUNTIME_CONFIG) --service node_manager)"; \
		curl -fsS "$$NODE_MANAGER_URL/healthz" >/dev/null
	@echo "$(GREEN) Runtime health checks passed$(NC)"

ensure-local-stack: render-runtime-config
	@echo "$(YELLOW)Ensuring the local validator stack is healthy...$(NC)"
	@if $(MAKE) --no-print-directory smoke-runtime >/dev/null 2>&1; then \
		echo "$(GREEN) Local validator stack already healthy$(NC)"; \
	else \
		runtime_ready=0; \
		for attempt in 1 2 3 4 5; do \
			echo "$(YELLOW) Waiting for runtime heartbeats (attempt $$attempt/5)...$(NC)"; \
			sleep 3; \
			if $(MAKE) --no-print-directory smoke-runtime >/dev/null 2>&1; then \
				runtime_ready=1; \
				echo "$(GREEN) Local validator stack became healthy$(NC)"; \
				break; \
			fi; \
		done; \
		if [ "$$runtime_ready" -eq 0 ]; then \
			echo "$(YELLOW) Local validator stack is not healthy yet; starting it now$(NC)"; \
			$(MAKE) --no-print-directory start-local-stack; \
		fi; \
	fi

test-e2e-json: build-program deploy-local verify-indexer-config ensure-indexer-ready
	@echo "$(YELLOW)Running bridge end-to-end test...$(NC)"
	@echo "$(YELLOW)  Chain state: real Anvil deposits + receipt MPT proofs$(NC)"
	@echo "$(YELLOW)  Proof:       mock Groth16 (SP1_PROVER=mock, fast dev mode)$(NC)"
	@mkdir -p "$$(dirname $(REPORT_SCENARIO_JSON))"
	@CHAIN_1_RPC_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id 31338)"; \
		BASE_CHAIN_RPC_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-rpc-url --config $(RUNTIME_CONFIG) --chain-id 31339)"; \
		RPC_URL_31338="$$CHAIN_1_RPC_URL" \
		RPC_URL_31339="$$BASE_CHAIN_RPC_URL" \
		SP1_PROVER=mock \
		RUST_LOG=info \
		cargo run -p bridge-script --bin test-bridge --release -- --json-out $(REPORT_SCENARIO_JSON)
	@echo "$(GREEN) Bridge e2e test passed$(NC)"
	@echo "$(YELLOW)  Scenario JSON: $(REPORT_SCENARIO_JSON)$(NC)"
	@CHAIN_1_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-port --config $(RUNTIME_CONFIG) --chain-id 31338)"; \
		BASE_CHAIN_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-port --config $(RUNTIME_CONFIG) --chain-id 31339)"; \
		echo "$(YELLOW)  Anvil nodes left running on ports $$CHAIN_1_PORT and $$BASE_CHAIN_PORT for indexer use.$(NC)"
	@echo "$(YELLOW)  Run 'make kill-anvil' when done.$(NC)"

test-e2e: test-e2e-json

test-live-bridge: ensure-local-stack
	@echo "$(YELLOW)Running live bridge deposit and claim...$(NC)"
	@mkdir -p "$$(dirname $(LIVE_BRIDGE_REPORT_JSON))"
	@cargo run -p bridge-script --bin exercise-bridge --release -- --config $(RUNTIME_CONFIG) --asset native --json-out $(LIVE_BRIDGE_REPORT_JSON)
	@echo "$(GREEN) Live bridge deposit and claim completed$(NC)"
	@echo "$(YELLOW)  Live bridge report: $(LIVE_BRIDGE_REPORT_JSON)$(NC)"
	@CHAIN_1_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-port --config $(RUNTIME_CONFIG) --chain-id 31338)"; \
		BASE_CHAIN_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-port --config $(RUNTIME_CONFIG) --chain-id 31339)"; \
		echo "$(YELLOW)  Runtime left running on chain ports $$CHAIN_1_PORT and $$BASE_CHAIN_PORT for the UI.$(NC)"

kill-anvil: render-runtime-config
	@CHAIN_IDS="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-ids --config $(RUNTIME_CONFIG) | tr '\n' ' ')"; \
		echo "$(YELLOW)Stopping managed Anvil instances for runtime $(RUNTIME_CONFIG)...$(NC)"; \
		for chain_id in $$CHAIN_IDS; do \
			chain_port="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- chain-port --config $(RUNTIME_CONFIG) --chain-id $$chain_id)"; \
			pid_file="$(RUNTIME_PID_DIR)/anvil-$$chain_id.pid"; \
			if [ -f "$$pid_file" ]; then \
				kill "$$(cat "$$pid_file")" 2>/dev/null || true; \
				rm -f "$$pid_file"; \
			fi; \
			lsof -ti tcp:$$chain_port | xargs kill 2>/dev/null || true; \
		done
	@sleep 1
	@echo "$(GREEN) Anvil stopped$(NC)"

upgrade-safety-check:
	@echo "$(YELLOW)Checking for unsafe upgrade skip flags...$(NC)"
	@if rg -n "unsafeSkipAllChecks\\s*=\\s*true" contracts >/dev/null; then \
		echo "$(RED)Unsafe upgrade configuration found (unsafeSkipAllChecks=true).$(NC)"; \
		rg -n "unsafeSkipAllChecks\\s*=\\s*true" contracts; \
		exit 1; \
	fi
	@echo "$(GREEN) Upgrade checks are in safe mode$(NC)"

bridge: upgrade-safety-check test-contracts test-contracts-fuzz test-components test-bridge test-e2e test-live-bridge
	@echo "$(GREEN) Full bridge pipeline complete$(NC)"

bridge-report:
	@echo "$(YELLOW)Running bridge validation report pipeline...$(NC)"
	@$(NPM) run scripts:run-bridge-validation --silent
	@echo "$(GREEN) Bridge report generated$(NC)"

ui-dev:
	@echo "$(YELLOW)Starting swap UI...$(NC)"
	@cd apps/web && $(NPM) run dev

ui-test:
	@echo "$(YELLOW)Running swap UI tests...$(NC)"
	@cd apps/web && $(NPM) run test --silent
	@cd apps/web && $(NPM) run test:e2e --silent
	@echo "$(GREEN) UI tests passed$(NC)"

update-indexer-config: render-runtime-config
	@echo "$(YELLOW)Updating indexer config with local contract addresses...$(NC)"
	@RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:update-indexer-config --silent
	@echo "$(GREEN) indexer/config.yaml updated$(NC)"

verify-indexer-config: render-runtime-config
	@echo "$(YELLOW)Verifying indexer config addresses match deploy artifacts...$(NC)"
	@RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:verify-indexer-config --silent
	@echo "$(GREEN) indexer/config.yaml is synchronized$(NC)"

restart-indexer: render-runtime-config
	@echo "$(YELLOW)Restarting Envio indexer...$(NC)"
	@HASURA_EXTERNAL_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- indexer-port --config $(RUNTIME_CONFIG))"; \
		INDEXER_PROJECT_NAME="bridge-indexer-$$HASURA_EXTERNAL_PORT"; \
		cd indexer && HASURA_EXTERNAL_PORT=$$HASURA_EXTERNAL_PORT docker compose -p $$INDEXER_PROJECT_NAME up -d --build
	@HASURA_EXTERNAL_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- indexer-port --config $(RUNTIME_CONFIG))"; \
		INDEXER_PROJECT_NAME="bridge-indexer-$$HASURA_EXTERNAL_PORT"; \
		cd indexer && HASURA_EXTERNAL_PORT=$$HASURA_EXTERNAL_PORT docker compose -p $$INDEXER_PROJECT_NAME ps
	@echo "$(YELLOW)Waiting 60 s for indexer to process events...$(NC)"
	@sleep 60
	@echo "$(GREEN) Indexer ready$(NC)"

reset-indexer: render-runtime-config
	@echo "$(YELLOW)Resetting Envio indexer state...$(NC)"
	@HASURA_EXTERNAL_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- indexer-port --config $(RUNTIME_CONFIG))"; \
		INDEXER_PROJECT_NAME="bridge-indexer-$$HASURA_EXTERNAL_PORT"; \
		cd indexer && HASURA_EXTERNAL_PORT=$$HASURA_EXTERNAL_PORT docker compose -p $$INDEXER_PROJECT_NAME down -v
	@HASURA_EXTERNAL_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- indexer-port --config $(RUNTIME_CONFIG))"; \
		INDEXER_PROJECT_NAME="bridge-indexer-$$HASURA_EXTERNAL_PORT"; \
		cd indexer && HASURA_EXTERNAL_PORT=$$HASURA_EXTERNAL_PORT docker compose -p $$INDEXER_PROJECT_NAME up -d --build
	@HASURA_EXTERNAL_PORT="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- indexer-port --config $(RUNTIME_CONFIG))"; \
		INDEXER_PROJECT_NAME="bridge-indexer-$$HASURA_EXTERNAL_PORT"; \
		cd indexer && HASURA_EXTERNAL_PORT=$$HASURA_EXTERNAL_PORT docker compose -p $$INDEXER_PROJECT_NAME ps
	@echo "$(YELLOW)Waiting 60 s for fresh indexer startup...$(NC)"
	@sleep 60
	@echo "$(GREEN) Fresh indexer ready$(NC)"

reset-runtime-state: runtime-dirs
	@echo "$(YELLOW)Clearing generated runtime state...$(NC)"
	@rm -f $(RUNTIME_STATE_DIR)/chain-manager.json $(RUNTIME_STATE_DIR)/node-manager.json $(RUNTIME_STATE_DIR)/sp1.json $(RUNTIME_STATE_DIR)/validators/*.json
	@echo "$(GREEN) Runtime state cleared$(NC)"

ensure-indexer-ready: render-runtime-config
	@echo "$(YELLOW)Polling Hasura until indexer is query-ready...$(NC)"
	@HASURA_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- indexer-url --config $(RUNTIME_CONFIG))"; \
		HASURA_SECRET="$${HASURA_SECRET:-$${HASURA_GRAPHQL_ADMIN_SECRET:-testing}}"; \
		$(NPM) run scripts:wait-indexer-ready --silent -- \
		--url "$$HASURA_URL" \
		--secret "$$HASURA_SECRET" \
		--timeout-ms 180000 \
		--interval-ms 3000
	@echo "$(GREEN) Indexer readiness confirmed$(NC)"

ensure-indexer-ready-existing: runtime-dirs
	@echo "$(YELLOW)Polling Hasura until indexer is query-ready...$(NC)"
	@HASURA_URL="$$(RUNTIME_CONFIG=$(RUNTIME_CONFIG) $(NPM) run scripts:runtime-config --silent -- indexer-url --config $(RUNTIME_CONFIG))"; \
		HASURA_SECRET="$${HASURA_SECRET:-$${HASURA_GRAPHQL_ADMIN_SECRET:-testing}}"; \
		$(NPM) run scripts:wait-indexer-ready --silent -- \
		--url "$$HASURA_URL" \
		--secret "$$HASURA_SECRET" \
		--timeout-ms 180000 \
		--interval-ms 3000
	@echo "$(GREEN) Indexer readiness confirmed$(NC)"
