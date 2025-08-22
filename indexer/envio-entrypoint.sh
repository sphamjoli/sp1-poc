#!/usr/bin/env sh

echo "Starting indexer..."
sleep 10

export TUI_OFF=${TUI_OFF}

echo "running indexer migrations..."
pnpm envio local db-migrate setup

echo "starting indexer..."
pnpm envio start
