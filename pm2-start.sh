#!/bin/bash
# Open Design PM2 wrapper
# tools-dev spawns daemon+web as background sidecars then exits.
# This script starts them, waits for ports, then tails the log to stay alive.

set -e
cd /home/phat/stack/open-design

# Kill any existing OD sidecars first
pkill -f 'open-design.*sidecar' 2>/dev/null || true
sleep 1

# Start daemon + web
pnpm tools-dev start web --daemon-port 7456 --web-port 7457

# Wait for both ports
for port in 7456 7457; do
  for i in $(seq 1 30); do
    if ss -tlnp | grep -q ":${port} "; then
      echo "Port ${port} ready"
      break
    fi
    sleep 1
  done
done

# Tail the log to keep PM2 process alive
LOG_DIR="/home/phat/stack/open-design/.tmp/tools-dev/default/logs"
mkdir -p "$LOG_DIR"
touch "$LOG_DIR/daemon/latest.log" "$LOG_DIR/web/latest.log"

echo "OD daemon+web running. Tailing logs..."
tail -F "$LOG_DIR/daemon/latest.log" "$LOG_DIR/web/latest.log" 2>/dev/null || \
  sleep infinity
