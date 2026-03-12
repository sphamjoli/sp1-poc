FROM node:22-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

CMD ["sh", "-lc", "npm run dev -- --host 0.0.0.0 --port ${UI_PORT:-4173}"]
