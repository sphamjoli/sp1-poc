#!/usr/bin/env sh
# OpenZeppelin Foundry invokes npx internally; only its locked local validator is supported.
set -eu
case "${1:-}" in
  '@openzeppelin/upgrades-core@^1.45.0'|'@openzeppelin/upgrades-core@1.46.0') shift ;;
  *) echo 'Only the locked OpenZeppelin upgrade validator is supported' >&2; exit 1 ;;
esac
exec bun /opt/upgrades/node_modules/@openzeppelin/upgrades-core/dist/cli/cli.js "$@"
