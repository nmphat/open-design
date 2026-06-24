#!/bin/bash
# Open Design PM2 wrapper
# tools-dev spawns daemon+web as background sidecars then exits.
# This script starts them, waits for ports, then tails the log to stay alive.
#
# Known issues fixed:
#   - Corepack pnpm@10.33.2 SIGABRT on Node 24.16.0 → use npx fallback
#   - @open-design/contracts not hoisted to root node_modules (pnpm strict)
#     → symlink before start so daemon ESM resolves from workspace root CWD

set -e
cd /home/phat/stack/open-design

# Kill any existing OD sidecars first
pkill -f 'open-design.*sidecar' 2>/dev/null || true
sleep 1

# Fix: ensure ALL @open-design/* workspace packages are resolvable from root.
# pnpm strict mode only symlinks into app-level node_modules/, but daemon
# spawns with CWD=workspaceRoot so ESM can't find packages not hoisted to root.
for dir in packages/* apps/* tools/*; do
  [ -d "$dir" ] || continue
  pkg_name=$(sed -n 's/.*"name": *"\(@open-design\/[^"]*\)".*/\1/p' "$dir/package.json" 2>/dev/null)
  [ -z "$pkg_name" ] && continue
  link_name="node_modules/${pkg_name}"
  if [ ! -e "$link_name" ]; then
    # compute relative path from node_modules/@open-design/ back to workspace
    rel=$(python3 -c "import os.path; print(os.path.relpath('$dir', 'node_modules/@open-design/'))")
    ln -sf "$rel" "$link_name"
    echo "Symlinked ${pkg_name} → ${rel}"
  fi
done

# Fix: corepack pnpm@10.33.2 crashes with SIGABRT on Node 24.16.0.
# Use npx to invoke the correct pnpm version as fallback.
PNPM_CMD="pnpm"
if ! pnpm --version >/dev/null 2>&1; then
  PNPM_CMD="npx -y pnpm@10.33.2"
  echo "Using npx fallback for pnpm (corepack crash detected)"
fi

# Start daemon + web
$PNPM_CMD tools-dev start web --daemon-port 7456 --web-port 7457

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
