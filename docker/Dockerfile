# syntax=docker/dockerfile:1
# Build context: repository root.
#   docker build -f docker/Dockerfile -t xara .
#   docker build -f docker/Dockerfile --build-arg REGISTERED=true -t xara:registered .

FROM rust:1.99.1-bookworm AS builder
ARG REGISTERED=false
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpulse-dev libasound2-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    set -eu; \
    features=""; \
    if [ "$REGISTERED" = "true" ]; then features="--features registered"; fi; \
    cargo build --locked --release -p xara $features; \
    install -D -m 0755 target/release/xara target/release/xara-monitor -t /out/

FROM debian:bookworm-slim
ARG REGISTERED=false
LABEL org.opencontainers.image.title="xara" \
      org.opencontainers.image.description="VARA-compatible modem" \
      org.opencontainers.image.source="https://github.com/x0rro/xara" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="0.1.3"
RUN apt-get update \
 && apt-get install -y --no-install-recommends libasound2 libpulse0 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && getent group plugdev >/dev/null || groupadd -r plugdev \
 && groupadd -g 1000 xara \
 && useradd -u 1000 -g xara -G audio,dialout,plugdev -M -d /state -s /usr/sbin/nologin xara \
 && mkdir -p /config /state && chown xara:xara /state
COPY --from=builder /out/xara /out/xara-monitor /usr/local/bin/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh
# Entrypoint adds --registered when XARA_REGISTERED is 1/true (only works in REGISTERED=true builds).
ENV XARA_REGISTERED=${REGISTERED} STATE_DIRECTORY=/state
USER xara
WORKDIR /state
VOLUME ["/state"]
EXPOSE 8300 8301 8100 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
