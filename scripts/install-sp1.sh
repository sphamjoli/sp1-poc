#!/usr/bin/env bash
set -euo pipefail

# Reuse only the exact reviewed CLI and its matching official guest compiler.
if [[ -x "$HOME/.sp1/bin/cargo-prove" ]] && \
  "$HOME/.sp1/bin/cargo-prove" prove --version | grep -Fq 'sp1 (2a51f3d ' && \
  rustup run succinct rustc --version | grep -Fxq 'rustc 1.91.1-dev'; then
  "$HOME/.sp1/bin/cargo-prove" prove --version
  exit 0
fi

installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/succinctlabs/sp1/2a51f3dd370e4c5f74d04dfd89359a13a7e93f99/sp1up/sp1up \
  -o "$installer"
expected=5865c5d94d7140083005738f078153b666af192501428d45bb5e27a57ef5ef87
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$installer" | cut -d ' ' -f 1)
else
  actual=$(shasum -a 256 "$installer" | cut -d ' ' -f 1)
fi
[[ "$actual" == "$expected" ]] || { echo 'SP1 installer checksum mismatch' >&2; exit 1; }
bash "$installer" --version 5.2.4
"$HOME/.sp1/bin/cargo-prove" prove --version | grep -F 'sp1 (2a51f3d '
rustup run succinct rustc --version | grep -Fx 'rustc 1.91.1-dev'
