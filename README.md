# Cloudflare WARP Proxy

A lightweight Docker container that runs [Cloudflare WARP](https://developers.cloudflare.com/warp-client/) as an HTTP proxy. Route your traffic through Cloudflare's network via a simple proxy endpoint.

## Quick Start

### Docker

```bash
docker run -d \
  --name warp-proxy \
  --cap-add=NET_ADMIN \
  -p 8888:8888 \
  -v warp-data:/var/lib/cloudflare-warp \
  ghcr.io/em411/cloudflare-warp-proxy:latest
```

### Docker Compose

```bash
docker compose up -d
```

Or with a WARP+ license key:

```bash
LICENSE_KEY=your-key-here docker compose up -d
```

## Configuration

| Variable | Description | Required |
|---|---|---|
| `LICENSE_KEY` | WARP+ license key for premium features | No |

The proxy listens on port `8888` and is accessible from private networks (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) by default.

### Persistent Registration

Mount `/var/lib/cloudflare-warp` as a volume to persist the WARP registration across container restarts. Without this, each restart creates a new device registration in Cloudflare, which counts against the 5-device limit for WARP+ license keys.

## Usage with Other Containers

Point any container's HTTP proxy to `warp-proxy:8888`. For example, with [Karakeep](https://github.com/karakeep-app/karakeep):

```yaml
services:
  warp-proxy:
    image: ghcr.io/em411/cloudflare-warp-proxy:latest
    container_name: warp-proxy
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    ports:
      - "8888:8888"
    volumes:
      - warp-data:/var/lib/cloudflare-warp
    environment:
      - LICENSE_KEY=${LICENSE_KEY:-}

  karakeep:
    image: ghcr.io/karakeep-app/karakeep:latest
    # ...
    environment:
      - HTTP_PROXY=http://warp-proxy:8888
      - HTTPS_PROXY=http://warp-proxy:8888

volumes:
  warp-data:
```

## How It Works

The container runs two processes managed by [tini](https://github.com/krallin/tini):

1. **Cloudflare WARP** (`warp-svc`) -- connects to Cloudflare's network and exposes a local proxy on port 40000
2. **tinyproxy** -- listens on port 8888 and forwards all traffic upstream to WARP

## Building

```bash
docker build --build-arg WARP_VERSION=<version> -t cloudflare-warp-proxy .
```

The `WARP_VERSION` argument is required and must match an available version in the [Cloudflare apt repository](https://pkg.cloudflareclient.com/).

## Requirements

- `NET_ADMIN` capability (required by WARP to create a tunnel)
- ~1GB RAM (inherent to the `warp-svc` daemon)
