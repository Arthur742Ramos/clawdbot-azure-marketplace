#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INSTALL_ROOT="/opt/clawdbot"
INSTALL_SCRIPTS="$INSTALL_ROOT/scripts"
INSTALL_DOCS="$INSTALL_ROOT/docs"
INSTALL_TEMPLATES="$INSTALL_ROOT/templates"

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

export DEBIAN_FRONTEND=noninteractive

fetch() {
  local url="$1"
  local dest="$2"
  curl -fsSL --retry 3 --retry-connrefused --connect-timeout 5 --max-time 60 "$url" -o "$dest"
}

install_motd() {
  log "Setting MOTD"
  cat > /etc/motd <<'MOTD'
==============================================================================
                         Clawdbot Azure Marketplace VM
==============================================================================

Next steps:
  1) Run: clawdbot-quickstart
  2) Try: clawdbot agent "hello world"
  3) Check service: systemctl --user status clawdbot-gateway.service

Tips:
  - OpenCode needs a PTY: ssh -tt <user>@<host>
  - Docs: /opt/clawdbot/README.md
MOTD
}

log "Installing system packages"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git jq unzip tar xz-utils

log "Installing Chromium (Playwright fallback)"
apt-get install -y --no-install-recommends chromium-browser 2>/dev/null || \
  apt-get install -y --no-install-recommends chromium || true

log "Installing GitHub CLI"
install -d -m 0755 /usr/share/keyrings
fetch https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  /usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list
apt-get update -y
apt-get install -y --no-install-recommends gh

NODE_MAJOR="${NODE_MAJOR:-22}"
log "Installing Node.js ${NODE_MAJOR}.x"
install -d -m 0755 /usr/share/keyrings
fetch https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  /usr/share/keyrings/nodesource.gpg.key
gpg --dearmor -o /usr/share/keyrings/nodesource.gpg /usr/share/keyrings/nodesource.gpg.key
rm -f /usr/share/keyrings/nodesource.gpg.key
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list
apt-get update -y
apt-get install -y --no-install-recommends nodejs
log "Node.js $(node --version) installed"

log "Installing Clawdbot and npm packages system-wide"
npm install -g clawdbot agent-browser playwright
log "Clawdbot $(clawdbot --version) installed"

INSTALL_PLAYWRIGHT_BROWSERS="${INSTALL_PLAYWRIGHT_BROWSERS:-1}"
if [[ "$INSTALL_PLAYWRIGHT_BROWSERS" -eq 1 ]]; then
  log "Installing Playwright Chromium browsers"
  install -d -m 0755 /usr/local/share/ms-playwright
  export PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/ms-playwright
  npx playwright install chromium
else
  warn "Skipping Playwright browser download (INSTALL_PLAYWRIGHT_BROWSERS=0)"
fi

INSTALL_OPENCODE="${INSTALL_OPENCODE:-1}"
if [[ "$INSTALL_OPENCODE" -eq 1 ]]; then
  log "Installing OpenCode"
  OPENCODE_URL="${OPENCODE_URL:-https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-x64.tar.gz}"
  OPENCODE_SHA256="${OPENCODE_SHA256:-}"
  tmp_file="$(mktemp)"
  fetch "$OPENCODE_URL" "$tmp_file"
  if [[ -n "$OPENCODE_SHA256" ]]; then
    echo "${OPENCODE_SHA256}  ${tmp_file}" | sha256sum -c -
  fi
  tar -xz -C /usr/local/bin -f "$tmp_file"
  rm -f "$tmp_file"
  chmod +x /usr/local/bin/opencode
  log "OpenCode $(opencode --version) installed"
else
  warn "Skipping OpenCode install (INSTALL_OPENCODE=0)"
fi

log "Installing Clawdbot assets"
install -d -m 0755 "$INSTALL_ROOT" "$INSTALL_SCRIPTS" "$INSTALL_DOCS" "$INSTALL_TEMPLATES"
if [[ -f "$REPO_ROOT/README.md" ]]; then
  install -m 0644 "$REPO_ROOT/README.md" "$INSTALL_ROOT/README.md"
fi
if [[ -f "$REPO_ROOT/docs/PUBLISHING.md" ]]; then
  install -m 0644 "$REPO_ROOT/docs/PUBLISHING.md" "$INSTALL_DOCS/PUBLISHING.md"
fi
if [[ -d "$REPO_ROOT/templates" ]]; then
  cp -a "$REPO_ROOT/templates/." "$INSTALL_TEMPLATES/"
fi

for script in setup.sh quickstart.sh first-login.sh first-boot.sh prepare-image.sh create-vm.sh capture-image.sh; do
  if [[ -f "$SCRIPT_DIR/$script" ]]; then
    install -m 0755 "$SCRIPT_DIR/$script" "$INSTALL_SCRIPTS/$script"
  else
    warn "Missing script: $SCRIPT_DIR/$script"
  fi
done

log "Creating symlinks in /usr/local/bin"
ln -sf "$INSTALL_SCRIPTS/setup.sh" /usr/local/bin/clawdbot-setup
ln -sf "$INSTALL_SCRIPTS/quickstart.sh" /usr/local/bin/clawdbot-quickstart
ln -sf "$INSTALL_SCRIPTS/first-login.sh" /usr/local/bin/clawdbot-first-login
ln -sf "$INSTALL_SCRIPTS/first-boot.sh" /usr/local/bin/clawdbot-first-boot
ln -sf "$INSTALL_SCRIPTS/prepare-image.sh" /usr/local/bin/clawdbot-prepare-image
ln -sf "$INSTALL_SCRIPTS/create-vm.sh" /usr/local/bin/clawdbot-create-vm
ln -sf "$INSTALL_SCRIPTS/capture-image.sh" /usr/local/bin/clawdbot-capture-image

log "Configuring global environment"
cat > /etc/profile.d/clawdbot.sh <<'PROFILE'
export UNDICI_NO_HTTP2=1
export PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/ms-playwright
if [ -f "$HOME/.config/clawdbot/env" ]; then
  . "$HOME/.config/clawdbot/env"
fi
PROFILE

log "Installing first-login hook"
cat > /etc/profile.d/clawdbot-first-login.sh <<'PROFILE'
if [ -x /usr/local/bin/clawdbot-first-login ]; then
  /usr/local/bin/clawdbot-first-login || true
fi
PROFILE

log "Installing systemd user service"
install -d -m 0755 /etc/systemd/user
if [[ -f "$REPO_ROOT/systemd/clawdbot-gateway.service" ]]; then
  install -m 0644 "$REPO_ROOT/systemd/clawdbot-gateway.service" \
    /etc/systemd/user/clawdbot-gateway.service
else
  warn "Missing systemd/clawdbot-gateway.service (service not installed)"
fi

install_motd

install -d -m 0755 /var/lib/clawdbot/secrets

log "Cleaning apt cache"
apt-get clean
rm -rf /var/lib/apt/lists/*

log "Setup complete!"
log "Next: users should run 'clawdbot-quickstart' on first login"

# Test: sudo ./scripts/setup.sh
# Test: INSTALL_OPENCODE=0 INSTALL_PLAYWRIGHT_BROWSERS=0 sudo ./scripts/setup.sh
