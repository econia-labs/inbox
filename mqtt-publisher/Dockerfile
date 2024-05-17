ARG APP_DIR=/app
ARG RUST_ROOT=.
ARG BIN_PATH=$APP_DIR/target/release/mqtt-publisher

FROM rust:slim-bookworm AS builder
ARG APP_DIR
ARG RUST_ROOT
COPY $RUST_ROOT $APP_DIR
WORKDIR $APP_DIR
RUN apt-get update && apt-get install -y --no-install-recommends \
    libudev-dev=252.22-1~deb12u1 \
    build-essential=12.9 \
    libclang-dev=1:14.0-55.7~deb12u1 \
    libpq-dev=15.6-0+deb12u1 \
    libssl-dev=3.0.11-1~deb12u2 \
    lld=1:14.0-55.7~deb12u1 \
    pkg-config=1.8.1-1 \
    && rm -rf /var/lib/apt/lists/*
RUN cargo build --release -p mqtt-publisher

FROM debian:bookworm-slim
ARG APP_DIR
ARG BIN_PATH
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev=15.6-0+deb12u1 \
        mosquitto=2.0.11-1.2+deb12u1

COPY --from=builder $BIN_PATH $APP_DIR/

COPY mosquitto.conf /mosquitto/config/mosquitto.conf

COPY acl_file /acl_file

RUN chown mosquitto:mosquitto /acl_file && \
    chmod 600 /acl_file

COPY start.sh /start.sh

ENV MQTT_URL=mqtt://127.0.0.1:21883

# This helps the container stop faster
STOPSIGNAL SIGKILL

CMD ["bash", "/start.sh"]
