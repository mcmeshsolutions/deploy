# Multi-arch production image for gatewayd
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS build
ARG TARGETPLATFORM
ARG TARGETARCH

WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY gatewayd ./gatewayd

# Install cross-compilation toolchain if target differs from build platform
RUN if [ "$TARGETARCH" = "arm64" ] && [ "$(uname -m)" != "aarch64" ]; then \
      apt-get update && apt-get install -y gcc-aarch64-linux-gnu && \
      rustup target add aarch64-unknown-linux-gnu && \
      CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
      cargo build --release --locked -p gatewayd --target aarch64-unknown-linux-gnu && \
      cp target/aarch64-unknown-linux-gnu/release/gatewayd target/release/gatewayd; \
    else \
      cargo build --release --locked -p gatewayd; \
    fi

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin mcmesh \
 && mkdir -p /data /backup && chown -R 10001:10001 /data /backup
COPY --from=build /src/target/release/gatewayd /usr/local/bin/gatewayd
USER 10001:10001
WORKDIR /data
ENV MCMESH_DB=/data/mcmesh.db MCMESH_CAS=/data/cas MCMESH_ADDR=0.0.0.0:8080
VOLUME ["/data", "/backup"]
EXPOSE 8080 9000 25565 24454/udp
HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD ["gatewayd", "status"]
ENTRYPOINT ["gatewayd"]
CMD ["serve"]
