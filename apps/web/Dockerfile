FROM oven/bun:1.4.2-debian

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

COPY . .

CMD ["sh", "-lc", "bun run dev -- --host 0.0.0.0 --port ${UI_PORT:-4173}"]
