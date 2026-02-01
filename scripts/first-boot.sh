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

MARKER="/var/lib/openclaw/first-boot.done"
if [[ -f "$MARKER" ]]; then
  log "First boot already completed"
  exit 0
fi

log "Writing welcome MOTD"
cat > /etc/motd <<'EOF'
==============================================================================
                         Openclaw Azure Marketplace VM
==============================================================================

This VM ships with:
  - Node.js 22.x
  - Openclaw + agent-browser
  - Playwright with Chromium
  - OpenCode
  - GitHub CLI
  - A user-level systemd service for the Openclaw gateway

Next steps:
  1) Run: openclaw-quickstart
  2) Try: openclaw agent "hello world"
  3) Check service: systemctl --user status openclaw-gateway.service

Tips:
  - OpenCode needs a PTY: ssh -tt <user>@<host>
  - Docs: /opt/openclaw/README.md
EOF

log "Enabling linger for all users (keeps gateway running after logout)"
for home_dir in /home/*; do
  [[ -d "$home_dir" ]] || continue
  user_name="$(basename "$home_dir")"
  if id "$user_name" &>/dev/null; then
    loginctl enable-linger "$user_name" 2>/dev/null || \
      warn "Could not enable linger for $user_name"
    log "Enabled linger for $user_name"
  fi
done

install -d -m 0755 /var/lib/openclaw
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKER"

log "First boot tasks complete"

# Test: sudo ./scripts/first-boot.sh
