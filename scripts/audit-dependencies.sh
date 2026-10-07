#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
bun audit
(cd apps/web && bun audit)
(cd indexer && pnpm audit)

# This exact development-only dependency exception is reviewed in the linked
# audit note. Version changes or expiry require a new review.
review_date=$(date -u +%Y-%m-%d)
if [[ "$review_date" > "2026-11-07" ]]; then
  echo "The OpenZeppelin tooling advisory exception expired; reassess the dependency before renewing the exception" >&2
  exit 1
fi
grep -Eq '"@openzeppelin/upgrades-core": "1.46.0"' contracts/package.json
grep -Eq '"elliptic": \["elliptic@6\.6\.1",' contracts/bun.lock
(cd contracts && bun audit --ignore GHSA-848j-6mx2-7j84)
