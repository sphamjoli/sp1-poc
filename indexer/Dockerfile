ARG ARCH=
FROM ${ARCH}mcr.microsoft.com/devcontainers/javascript-node:20-bookworm

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

WORKDIR /app/base-template

RUN npm install -g npm@latest
RUN corepack enable
RUN npm install --global pnpm

COPY . .

RUN pnpm install --force --config.confirmModulesPurge=false
RUN pnpm envio codegen

RUN chmod +x envio-entrypoint.sh

CMD ["./envio-entrypoint.sh"]
