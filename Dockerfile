ARG DEBIAN_VERSION=bookworm-slim
ARG TINYPROXY_VERSION=1.11.2

# Stage 1: Build tinyproxy with upstream support
FROM docker.io/debian:${DEBIAN_VERSION} AS tinyproxy-builder
ARG TINYPROXY_VERSION
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential curl ca-certificates && \
    curl -fsSL -o tinyproxy.tar.gz \
      "https://github.com/tinyproxy/tinyproxy/releases/download/${TINYPROXY_VERSION}/tinyproxy-${TINYPROXY_VERSION}.tar.gz" && \
    tar xzf tinyproxy.tar.gz && \
    cd "tinyproxy-${TINYPROXY_VERSION}" && \
    ./configure --enable-upstream && \
    make -j"$(nproc)" && \
    cp src/tinyproxy /usr/local/bin/tinyproxy

# Stage 2: Install cloudflare-warp
FROM docker.io/debian:${DEBIAN_VERSION} AS warp
ARG WARP_VERSION
ARG DEBIAN_FRONTEND=noninteractive
RUN test -n "${WARP_VERSION}" || { echo "WARP_VERSION build arg is required" >&2; exit 1; } && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      gnupg ca-certificates curl lsb-release tini && \
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
      | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends "cloudflare-warp=${WARP_VERSION}" && \
    apt-get purge -y gnupg lsb-release && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Stage 3: Final image
FROM warp AS final

COPY --from=tinyproxy-builder /usr/local/bin/tinyproxy /usr/bin/tinyproxy
COPY run.sh tinyproxy.conf /

RUN chmod +x /run.sh

EXPOSE 8888

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD warp-cli --accept-tos status 2>/dev/null | grep -q Connected || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/run.sh"]
