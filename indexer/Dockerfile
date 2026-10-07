ARG ARCH=
FROM ${ARCH}mcr.microsoft.com/devcontainers/javascript-node:22-bookworm

COPY --from=oven/bun:1.4.2-debian /usr/local/bin/bun /usr/local/bin/bun

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

WORKDIR /app/base-template

RUN corepack enable
RUN corepack prepare pnpm@10.17.1 --activate

COPY . .

RUN pnpm install --frozen-lockfile
RUN pnpm run codegen

RUN chmod +x envio-entrypoint.sh

CMD ["./envio-entrypoint.sh"]
