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

export DEBIAN_FRONTEND=noninteractive

# ─────────────────────────────────────────────────────────────────────────────
# System packages
# ─────────────────────────────────────────────────────────────────────────────

log "Installing system packages"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git jq unzip

# Chromium for Playwright fallback
apt-get install -y --no-install-recommends chromium-browser 2>/dev/null || \
  apt-get install -y --no-install-recommends chromium || true

# ─────────────────────────────────────────────────────────────────────────────
# Node.js (via NodeSource)
# ─────────────────────────────────────────────────────────────────────────────

NODE_MAJOR="${NODE_MAJOR:-22}"
log "Installing Node.js ${NODE_MAJOR}.x"
install -d /usr/share/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list
apt-get update -y
apt-get install -y --no-install-recommends nodejs

log "Node.js $(node --version) installed"

# ─────────────────────────────────────────────────────────────────────────────
# Clawdbot + npm packages (SYSTEM-WIDE)
# ─────────────────────────────────────────────────────────────────────────────

log "Installing Clawdbot and npm packages system-wide"
npm install -g clawdbot agent-browser playwright

log "Clawdbot $(clawdbot --version) installed"

# ─────────────────────────────────────────────────────────────────────────────
# OpenCode binary
# ─────────────────────────────────────────────────────────────────────────────

log "Installing OpenCode"
OPENCODE_URL="https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-x64.tar.gz"
curl -fsSL "$OPENCODE_URL" | tar -xz -C /usr/local/bin
chmod +x /usr/local/bin/opencode
log "OpenCode $(opencode --version) installed"

# ─────────────────────────────────────────────────────────────────────────────
# MOTD
# ─────────────────────────────────────────────────────────────────────────────

log "Setting MOTD"
cat > /etc/motd << 'MOTD'
╔═══════════════════════════════════════════════════════════════╗
║                       CLAWDBOT VM                             ║
║                                                               ║
║  Run 'clawdbot onboard' to complete setup                     ║
║  Docs: https://docs.clawd.bot                                 ║
╚═══════════════════════════════════════════════════════════════╝
MOTD

# ─────────────────────────────────────────────────────────────────────────────
# Profile environment (for new users)
# ─────────────────────────────────────────────────────────────────────────────

log "Configuring global environment"
cat > /etc/profile.d/clawdbot.sh << 'PROFILE'
# Clawdbot environment
export UNDICI_NO_HTTP2=1
PROFILE

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────

log "Cleaning apt cache"
apt-get clean
rm -rf /var/lib/apt/lists/*

log "Setup complete!"
log "NOTE: Users should run 'npx playwright install chromium' on first login"
log "      or include it in cloud-init for the deployed VM."
