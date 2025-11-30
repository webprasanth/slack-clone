# ---------- Base image with OpenSSL (needed for Prisma) ----------
FROM node:20-bullseye AS base
WORKDIR /app

# Install OpenSSL so Prisma's query engine (openssl-1.1.x) works
RUN apt-get update -y && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

ENV NEXT_TELEMETRY_DISABLED=1


# ---------- Dependencies stage ----------
FROM base AS deps

# Copy only dependency manifests for caching
COPY package.json package-lock.json* yarn.lock* ./

RUN \
  if [ -f package-lock.json ]; then npm ci; \
  elif [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
  else npm install; \
  fi


# ---------- Build stage ----------
FROM base AS builder

# Bring in node_modules from deps
COPY --from=deps /app/node_modules ./node_modules

# Copy the rest of the project (src, prisma, configs, .env, etc.)
COPY . .

# Generate Prisma client
RUN npx prisma generate

# Build Next.js app
RUN npm run build


# ---------- Runtime stage ----------
FROM base AS runner

ENV NODE_ENV=production

# Create non-root user for safety
RUN groupadd -r nodejs && useradd -r -g nodejs nodejs
USER nodejs

# Copy built app and runtime dependencies
# Copy built Next.js output
COPY --from=builder /app/.next ./.next

# Copy package.json so npm start works
COPY --from=builder /app/package.json ./package.json

# Copy node_modules for runtime
COPY --from=deps /app/node_modules ./node_modules

# Copy Prisma schema & migrations
COPY --from=builder /app/prisma ./prisma

# If "public" exists, copy it (optional + safe)
# COPY --from=builder /app/public ./public

# Note:
# DATABASE_URL="file:./dev.db" -> Prisma will create /app/dev.db inside the container.

EXPOSE 3000

# On container start:
# 1) Apply migrations (creates/updates dev.db)
# 2) Start Next.js
# CMD sh -c "npx prisma migrate deploy && npm start"

# For SQLite/dev: synchronize schema to the DB, then start Next.js
CMD sh -c "npx prisma db push && npm start"

