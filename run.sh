#!/bin/bash
set -euo pipefail

WARP_PORT=40000
MAX_RETRIES=30

warp_cli() {
	warp-cli --accept-tos "$@"
}

warp-svc > /dev/null 2>&1 &
WARP_PID=$!
trap 'kill ${WARP_PID} 2>/dev/null' EXIT TERM INT

# Wait for warp-svc and register (skip if already registered)
retries=0
while ! warp_cli registration show 2>/dev/null; do
	if warp_cli registration new 2>/dev/null; then
		continue
	fi
	retries=$((retries + 1))
	if [ "${retries}" -ge "${MAX_RETRIES}" ]; then
		echo "Failed to register after ${MAX_RETRIES} attempts, giving up" >&2
		exit 1
	fi
	echo "Awaiting warp-svc to become online... (${retries}/${MAX_RETRIES})" >&2
	sleep 2
done

echo "Setting WARP mode to proxy..."
warp_cli mode proxy

echo "Setting WARP proxy port to ${WARP_PORT}..."
warp_cli proxy port "${WARP_PORT}"

if [ -n "${LICENSE_KEY:-}" ]; then
	echo "Applying license key..."
	warp_cli registration license "${LICENSE_KEY}"
fi

echo "Connecting to WARP..."
warp_cli connect

# Wait for WARP to establish connection
retries=0
while true; do
	if warp_cli status 2>/dev/null | grep -q "Connected"; then
		break
	fi
	retries=$((retries + 1))
	if [ "${retries}" -ge "${MAX_RETRIES}" ]; then
		echo "WARP failed to connect after ${MAX_RETRIES} attempts, giving up" >&2
		exit 1
	fi
	echo "Waiting for WARP to connect... (${retries}/${MAX_RETRIES})" >&2
	sleep 2
done

echo "WARP connected, starting tinyproxy on port 8888..."
exec /usr/bin/tinyproxy -d -c /tinyproxy.conf
