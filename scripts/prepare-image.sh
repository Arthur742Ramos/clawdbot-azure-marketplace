#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$SCRIPT_NAME" "$*"; }
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

if [[ "${1:-}" != "--force" ]]; then
  cat <<'EOF' >&2
Usage: ./prepare-image.sh --force

This will deprovision the VM for image capture. It removes SSH keys,
credential caches, tokens, and user history, clears logs, and runs
waagent -deprovision+user.
EOF
  exit 1
fi

log "Stopping user gateway services where possible"
for home_dir in /home/*; do
  [[ -d "$home_dir" ]] || continue
  user_name="$(basename "$home_dir")"
  if [[ -f "$home_dir/.config/systemd/user/clawdbot-gateway.service" || \
        -f "/etc/systemd/user/clawdbot-gateway.service" ]]; then
    user_id="$(id -u "$user_name" 2>/dev/null || true)"
    if [[ -n "$user_id" ]]; then
      runtime_dir="/run/user/$user_id"
      if [[ -d "$runtime_dir" ]]; then
        sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
          systemctl --user stop clawdbot-gateway.service || true
      fi
    fi
  fi
done

log "Removing SSH host keys"
rm -f /etc/ssh/ssh_host_*

log "Removing user SSH keys, tokens, and history"
for home_dir in /root /home/*; do
  [[ -d "$home_dir" ]] || continue

  rm -f "$home_dir/.bash_history" "$home_dir/.zsh_history" || true
  rm -f "$home_dir/.ssh/authorized_keys" "$home_dir/.ssh/known_hosts" || true
  rm -rf "$home_dir/.ssh" || true

  rm -rf "$home_dir/.config/clawdbot" \
    "$home_dir/.config/gh" \
    "$home_dir/.config/opencode" \
    "$home_dir/.config/github-copilot" || true

  rm -rf "$home_dir/.local/share/gh" \
    "$home_dir/.local/share/opencode" \
    "$home_dir/.local/share/clawdbot" || true

  rm -rf "$home_dir/.cache/clawdbot" \
    "$home_dir/.cache/gh" \
    "$home_dir/.cache/opencode" \
    "$home_dir/.cache/ms-playwright" || true

  rm -rf "$home_dir/.azure" "$home_dir/.npm" || true

  rm -f "$home_dir/.config/systemd/user/clawdbot-gateway.service.d/10-copilot.conf" || true
done

log "Removing Clawdbot machine state"
rm -rf /var/lib/clawdbot/secrets /var/lib/clawdbot/first-boot.done

log "Resetting machine-id"
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

log "Clearing logs and temporary files"
rm -f /var/log/wtmp /var/log/btmp /var/log/lastlog
find /var/log -type f -exec truncate -s 0 {} + || true
if command -v journalctl >/dev/null 2>&1; then
  journalctl --rotate || true
  journalctl --vacuum-time=1s || true
fi
rm -rf /tmp/* /var/tmp/*

log "Resetting cloud-init state"
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init clean --logs || true
else
  rm -rf /var/lib/cloud/*
fi

log "Leaving first-run breadcrumbs"
install -d -m 0755 /var/lib/clawdbot
cat > /var/lib/clawdbot/README_FIRST_RUN.txt <<'EOF'
Welcome to Clawdbot on Azure Marketplace.

Next steps:
  1) SSH into the VM
  2) Run: clawdbot-quickstart
  3) Try: clawdbot agent "hello world"

Tips:
  - OpenCode needs a PTY: ssh -tt <user>@<host>
  - Docs: /opt/clawdbot/README.md
EOF

if command -v waagent >/dev/null 2>&1; then
  log "Running waagent deprovision"
  waagent -deprovision+user -force
else
  warn "waagent not found; skipping deprovision"
fi

sync
log "Image preparation complete. Shut down the VM before capture."

# Test: sudo ./scripts/prepare-image.sh --force
