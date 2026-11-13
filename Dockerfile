# Not built in CI yet: check it on your own machine before relying on it.
FROM rust:1-bookworm AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY gatewayd ./gatewayd
RUN cargo build --release --locked -p gatewayd

FROM debian:bookworm-slim
# a fixed unprivileged id, so a bind-mounted data directory can be chowned to it
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin mcmesh \
 && mkdir /data && chown 10001:10001 /data
COPY --from=build /src/target/release/gatewayd /usr/local/bin/gatewayd
USER 10001:10001
WORKDIR /data
ENV MCMESH_DB=/data/mcmesh.db MCMESH_CAS=/data/cas MCMESH_ADDR=0.0.0.0:8080
VOLUME /data
EXPOSE 8080 9000 25565 24454/udp
HEALTHCHECK --interval=60s --timeout=10s CMD ["gatewayd", "status"]
ENTRYPOINT ["gatewayd"]
CMD ["serve"]
