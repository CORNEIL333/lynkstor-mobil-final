# Lynkstor — API + dashboard admin (monolithe)
# Secrets obligatoires en production : ADMIN_API_KEY, ADMIN_PASSWORD, WEBHOOK_SECRET
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

RUN mkdir -p /app/data

EXPOSE 8080

ENV PORT=8080
ENV NODE_ENV=production
ENV DATA_DIR=/app/data

# Healthcheck pour Render / orchestrateurs
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["node", "index.js"]
