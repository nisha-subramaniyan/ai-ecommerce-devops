# ---- Backend image (multi-stage, non-root) ----
# Stage 1: install production dependencies only
FROM node:20-alpine AS deps
WORKDIR /app
COPY application/backend/package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

# Stage 2: small runtime image
FROM node:20-alpine

# Update npm and its bundled dependencies to address the vulnerable tar
# npm is not required at runtime; remove its bundled dependencies
RUN rm -rf /usr/local/lib/node_modules/npm \
           /usr/local/bin/npm \
           /usr/local/bin/npx

ENV NODE_ENV=production PORT=3000
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY application/backend/package*.json ./
COPY application/backend/src ./src
# 'node' is a built-in unprivileged user in the official image (least privilege)
USER node
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1
CMD ["node", "src/server.js"]
