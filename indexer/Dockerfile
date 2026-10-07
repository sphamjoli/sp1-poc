ARG ARCH=
FROM ${ARCH}mcr.microsoft.com/devcontainers/javascript-node:22-bookworm

COPY --from=oven/bun:1.4.2-debian /usr/local/bin/bun /usr/local/bin/bun

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

WORKDIR /workspace

RUN corepack enable
RUN corepack prepare pnpm@10.17.1 --activate

COPY config/chains ./config/chains
COPY scripts/generate-chain-metadata.ts scripts/chain-metadata.ts ./scripts/
COPY indexer ./indexer
RUN bun scripts/generate-chain-metadata.ts
WORKDIR /workspace/indexer

RUN pnpm install --frozen-lockfile
RUN pnpm run codegen
RUN pnpm run build

RUN chmod +x envio-entrypoint.sh

CMD ["./envio-entrypoint.sh"]
