#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; }
die() { err "$*"; exit 1; }

on_error() {
  err "Failed at line $LINENO: $BASH_COMMAND"
}

on_interrupt() {
  err "Cancelled by user."
  exit 130
}

trap on_error ERR
trap on_interrupt INT TERM

if [[ "${EUID}" -ne 0 ]]; then
  die "Run as root (sudo)"
fi

MARKER="/var/lib/clawdbot/first-boot.done"
if [[ -f "$MARKER" ]]; then
  log "First boot already completed"
  exit 0
fi

log "Writing welcome MOTD"
cat > /etc/motd <<'EOF'
==============================================================================
                         Clawdbot Azure Marketplace VM
==============================================================================

This VM ships with:
  - Node.js 22.x
  - Clawdbot + agent-browser
  - Playwright with Chromium
  - OpenCode
  - GitHub CLI
  - A user-level systemd service for the Clawdbot gateway

Next steps:
  1) Run: clawdbot-quickstart
  2) Try: clawdbot agent "hello world"
  3) Check service: systemctl --user status clawdbot-gateway.service

Tips:
  - OpenCode needs a PTY: ssh -tt <user>@<host>
  - Docs: /opt/clawdbot/README.md
EOF

install -d -m 0755 /var/lib/clawdbot
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKER"

log "First boot tasks complete"

# Test: sudo ./scripts/first-boot.sh
