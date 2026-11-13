#!/bin/bash
set -euo pipefail

WARP_PORT=40000
MAX_RETRIES=30

warp_cli() {
	warp-cli --accept-tos "$@"
}

warp-svc > /dev/null 2>&1 &
WARP_PID=$!
PROXY_PID=""

# Stop both daemons whenever the script ends, whatever the reason
cleanup() {
	trap - EXIT
	kill ${PROXY_PID} "${WARP_PID}" 2>/dev/null || true
	wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT

require_warp_svc() {
	if ! kill -0 "${WARP_PID}" 2>/dev/null; then
		echo "warp-svc is not running, giving up" >&2
		exit 1
	fi
}

# Wait for warp-svc and register (skip if already registered).
# Output is discarded: "registration show" prints the account ID and license key.
retries=0
while ! warp_cli registration show > /dev/null 2>&1; do
	require_warp_svc
	if warp_cli registration new > /dev/null 2>&1; then
		echo "Registered a new WARP device"
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
	warp_cli registration license "${LICENSE_KEY}" > /dev/null
fi

echo "Connecting to WARP..."
warp_cli connect

# Wait for WARP to establish connection
retries=0
while true; do
	require_warp_svc
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
/usr/bin/tinyproxy -d -c /tinyproxy.conf &
PROXY_PID=$!

# The container is only useful while both daemons run. Exit as soon as either
# one dies (for example warp-svc killed at a memory limit) so the restart
# policy brings the whole container back instead of leaving a dead proxy.
set +e
wait -n "${WARP_PID}" "${PROXY_PID}"
code=$?
set -e

if kill -0 "${WARP_PID}" 2>/dev/null; then
	echo "tinyproxy exited (status ${code}), stopping container" >&2
else
	echo "warp-svc exited (status ${code}), stopping container" >&2
fi
exit 1
