#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

check_syntax() {
  git diff --check
  while IFS= read -r -d '' file; do
    if [[ "$file" == *.sh || "$file" == .githooks/* ]]; then bash -n "$file"; fi
  done < <(git ls-files -z)
}
check_format() {
  cargo fmt --all -- --check
}
check_host() {
  cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
  cargo test --workspace --all-features --locked
}
check_guest() {
  cargo test -p bridge-program --no-default-features --locked
  (cd crates/bridge-program && cargo prove build --locked)
  elf=target/elf-compilation/riscv32im-succinct-zkvm-elf/release/bridge-program
  test -s "$elf"
  printf 'SP1 guest ELF size (bytes): '
  wc -c < "$elf"
}
check_docs() {
  RUSTDOCFLAGS="-D warnings" cargo doc --workspace --all-features --no-deps --locked
}
check_rust() {
  check_format
  check_host
  check_guest
  check_docs
}
check_web() {
  bun run typecheck
  bun run test
  (cd apps/web && bun run build && bun run test && bun run test:e2e)
}
check_indexer() {
  bun scripts/generate-chain-metadata.ts
  (cd indexer && bun run codegen && pnpm --dir generated audit && bun run build && bun run mocha)
}
check_contracts() (
  cargo build -p validator-utils --bin validator-utils --locked
  export ETH_RPC_URL="http://127.0.0.1:18545"
  export BASE_RPC_URL="http://127.0.0.1:18546"
  anvil --host 127.0.0.1 --port 18545 --chain-id 1 --code-size-limit 999999 --silent &
  first_pid=$!
  anvil --host 127.0.0.1 --port 18546 --chain-id 8453 --code-size-limit 999999 --silent &
  second_pid=$!
  trap 'kill "$first_pid" "$second_pid" 2>/dev/null || true' EXIT
  ready=false
  for attempt in $(seq 1 30); do
    kill -0 "$first_pid" && kill -0 "$second_pid" || exit 1
    if cast chain-id --rpc-url "$ETH_RPC_URL" >/dev/null 2>&1 && cast chain-id --rpc-url "$BASE_RPC_URL" >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 1
  done
  test "$ready" = true || { echo "Fixture chains did not become ready" >&2; exit 1; }
  cd contracts
  forge fmt --check
  forge clean
  forge build
  forge test --fuzz-runs 1000
)
case "${1:-all}" in
  syntax) check_syntax ;;
  fmt) check_format ;;
  host) check_host ;;
  guest) check_guest ;;
  docs) check_docs ;;
  rust) check_rust ;;
  web) check_web ;;
  indexer) check_indexer ;;
  contracts) check_contracts ;;
  all) check_syntax; check_rust; check_web; check_indexer; check_contracts ;;
  *) echo "Usage: $0 [syntax|fmt|host|guest|docs|rust|web|indexer|contracts|all]" >&2; exit 2 ;;
esac
