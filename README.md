# Cloudflare Warp Proxy

Just a basic proxy server for cloudflare so you can bounce requests from a Cloudflare IP

## Usage

```bash
docker run -rm -p 8888:8888 --cap-add=NET_ADMIN ghcr.io/em411/cloudflare-warp-proxy:latest
```
