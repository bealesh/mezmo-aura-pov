# Stage 1: Build Aura from source
FROM rust:1.82-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clone the official Mezmo Aura repository
ARG AURA_REF=main
RUN git clone --depth=1 --branch ${AURA_REF} \
    https://github.com/mezmo/aura.git .

# Cache dependencies before building the binary
RUN cargo fetch

RUN cargo build --release --bin aura-web-server

# Stage 2: Minimal runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/aura-web-server /usr/local/bin/aura-web-server

# Config directory — mounted at runtime via compose volume
RUN mkdir -p /app/config

EXPOSE 3030

HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=20s \
    CMD curl -sf http://localhost:3030/health || exit 1

CMD ["aura-web-server"]
