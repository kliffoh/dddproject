# DDD AI Workforce v6 — production image
FROM node:22-bookworm-slim

ENV NODE_ENV=production \
    DDD_DATA_DIR=/data \
    HOST=0.0.0.0 \
    PORT=8765 \
    TRUST_PROXY=1

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY server.js .env.example ./
COPY src ./src
COPY public ./public
COPY tools ./tools
COPY deploy/docker-entrypoint.sh /usr/local/bin/ddd-entrypoint
RUN chmod +x /usr/local/bin/ddd-entrypoint && mkdir -p /data

VOLUME ["/data"]
EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8765)+'/api/ready').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["ddd-entrypoint"]
CMD ["node", "server.js"]
