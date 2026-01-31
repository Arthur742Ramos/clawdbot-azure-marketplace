#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
err() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; }
die() { err "$*"; exit 1; }

trap 'err "Failed at line $LINENO: $BASH_COMMAND"' ERR

if [[ "${EUID}" -ne 0 ]]; then
  die "Run as root (sudo)"
fi

if [[ "${1:-}" != "--force" ]]; then
  cat <<'EOF' >&2
Usage: ./prepare-image.sh --force

This will deprovision the VM for image capture. It removes SSH keys,
credential caches, and user history, and runs waagent -deprovision+user.
EOF
  exit 1
fi

log "Stopping user gateway services where possible"
for home_dir in /home/*; do
  [[ -d "$home_dir" ]] || continue
  user_name="$(basename "$home_dir")"
  if [[ -f "$home_dir/.config/systemd/user/clawdbot-gateway.service" ]]; then
    user_id="$(id -u "$user_name")"
    runtime_dir="/run/user/$user_id"
    if [[ -d "$runtime_dir" ]]; then
      sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user stop clawdbot-gateway.service || true
    fi
  fi
done

log "Removing SSH host keys"
rm -f /etc/ssh/ssh_host_*

log "Removing user SSH keys and history"
for home_dir in /root /home/*; do
  [[ -d "$home_dir" ]] || continue
  rm -f "$home_dir/.bash_history"
  rm -f "$home_dir/.ssh/authorized_keys"
  rm -f "$home_dir/.ssh/"*
  rmdir "$home_dir/.ssh" 2>/dev/null || true
  rm -rf "$home_dir/.config/clawdbot" "$home_dir/.config/gh" "$home_dir/.azure"
  rm -rf "$home_dir/.cache/clawdbot" "$home_dir/.cache/azure"
done

log "Clearing logs and temporary files"
rm -f /var/log/wtmp /var/log/btmp /var/log/lastlog
find /var/log -type f -name "*.log" -exec truncate -s 0 {} + || true
if command -v journalctl >/dev/null 2>&1; then
  journalctl --rotate || true
  journalctl --vacuum-time=1s || true
fi
rm -rf /tmp/* /var/tmp/*

log "Resetting cloud-init state"
rm -rf /var/lib/cloud/*

if command -v waagent >/dev/null 2>&1; then
  log "Running waagent deprovision"
  waagent -deprovision+user -force
else
  log "waagent not found; skipping deprovision"
fi

sync
log "Image preparation complete. Shut down the VM before capture."
