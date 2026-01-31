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

TARGET_USER="${CLAWDBOT_USER:-${SUDO_USER:-}}"
if [[ -z "$TARGET_USER" ]]; then
  TARGET_USER="$(logname 2>/dev/null || true)"
fi
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
  die "Unable to determine target user. Set CLAWDBOT_USER to a non-root user."
fi

USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
  die "Home directory not found for user: $TARGET_USER"
fi

USER_ID="$(id -u "$TARGET_USER")"
NPM_PREFIX="${USER_HOME}/.npm-global"
RUN_AS_USER=(sudo -u "$TARGET_USER" -H env HOME="$USER_HOME")

export DEBIAN_FRONTEND=noninteractive

ensure_line() {
  local file="$1"
  local line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -qxF "$line" "$file"; then
    echo "$line" >> "$file"
  fi
}

install_system_packages() {
  log "Installing system packages"
  apt-get update -y
  apt-get install -y --no-install-recommends ca-certificates curl gnupg git jq
  if ! apt-get install -y --no-install-recommends chromium-browser; then
    log "chromium-browser not available, installing chromium"
    apt-get install -y --no-install-recommends chromium
  fi
}

install_nodesource() {
  local node_major="${NODE_MAJOR:-22}"
  log "Adding NodeSource repository for Node.js ${node_major}.x"
  install -d /usr/share/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
  echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${node_major}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -y
  apt-get install -y --no-install-recommends nodejs
}

configure_npm() {
  log "Configuring npm global prefix"
  install -d -m 0755 "$NPM_PREFIX"
  "${RUN_AS_USER[@]}" npm config set prefix "$NPM_PREFIX"
  ensure_line "$USER_HOME/.profile" 'export PATH="$HOME/.npm-global/bin:$PATH"'
  ensure_line "$USER_HOME/.profile" 'export UNDICI_NO_HTTP2=1'
  ensure_line "$USER_HOME/.bashrc" 'export PATH="$HOME/.npm-global/bin:$PATH"'
  ensure_line "$USER_HOME/.bashrc" 'export UNDICI_NO_HTTP2=1'
  chown "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.profile" "$USER_HOME/.bashrc"
}

install_npm_globals() {
  log "Installing npm global packages"
  "${RUN_AS_USER[@]}" env PATH="$NPM_PREFIX/bin:/usr/local/bin:/usr/bin:/bin" npm install -g \
    clawdbot \
    agent-browser \
    playwright
}

install_playwright_browser() {
  log "Installing Playwright Chromium browser"
  if [[ -x "$NPM_PREFIX/bin/playwright" ]]; then
    "${RUN_AS_USER[@]}" env PATH="$NPM_PREFIX/bin:/usr/local/bin:/usr/bin:/bin" \
      "$NPM_PREFIX/bin/playwright" install chromium
  else
    die "Playwright binary not found at $NPM_PREFIX/bin/playwright"
  fi
}

install_opencode() {
  if [[ "${INSTALL_OPENCODE:-0}" != "1" ]]; then
    log "Skipping OpenCode install (INSTALL_OPENCODE=1 to enable)"
    return 0
  fi
  if [[ -z "${OPENCODE_URL:-}" ]]; then
    die "INSTALL_OPENCODE=1 requires OPENCODE_URL to be set"
  fi
  log "Installing OpenCode binary"
  curl -fsSL "$OPENCODE_URL" -o /usr/local/bin/opencode
  chmod 0755 /usr/local/bin/opencode
  if [[ -n "${OPENCODE_SHA256:-}" ]]; then
    echo "${OPENCODE_SHA256}  /usr/local/bin/opencode" | sha256sum -c -
  fi
}

configure_systemd_service() {
  log "Configuring user systemd service for clawdbot-gateway"
  local service_dir="$USER_HOME/.config/systemd/user"
  install -d -m 0755 "$service_dir"
  cat > "$service_dir/clawdbot-gateway.service" <<'EOF'
[Unit]
Description=Clawdbot Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PATH=%h/.npm-global/bin:/usr/local/bin:/usr/bin:/bin
Environment=UNDICI_NO_HTTP2=1
ExecStart=%h/.npm-global/bin/clawdbot gateway start
Restart=always
RestartSec=5
StartLimitIntervalSec=0

[Install]
WantedBy=default.target
EOF
  chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.config/systemd"

  loginctl enable-linger "$TARGET_USER"

  local runtime_dir="/run/user/$USER_ID"
  if [[ ! -d "$runtime_dir" ]]; then
    mkdir -p "$runtime_dir"
    chown "$TARGET_USER":"$TARGET_USER" "$runtime_dir"
    chmod 0700 "$runtime_dir"
  fi

  if sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user daemon-reload; then
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user enable --now clawdbot-gateway.service
  else
    log "systemctl --user unavailable; enabling service symlink"
    install -d -m 0755 "$service_dir/default.target.wants"
    ln -sf "$service_dir/clawdbot-gateway.service" \
      "$service_dir/default.target.wants/clawdbot-gateway.service"
    chown -h "$TARGET_USER":"$TARGET_USER" "$service_dir/default.target.wants/clawdbot-gateway.service"
  fi
}

main() {
  install_system_packages
  install_nodesource
  configure_npm
  install_npm_globals
  install_playwright_browser
  install_opencode
  configure_systemd_service
  log "Setup complete for user: $TARGET_USER"
}

main "$@"
