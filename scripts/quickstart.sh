#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
ORIGINAL_ARGS=("$@")

if [[ "${EUID}" -eq 0 ]]; then
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    exec sudo -u "$SUDO_USER" -H "$0" "${ORIGINAL_ARGS[@]}"
  fi
  printf '%s\n' "Run this as a regular user, not root." >&2
  exit 1
fi

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD="$(printf '\033[1m')"
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  RESET="$(printf '\033[0m')"
else
  BOLD=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  RESET=""
fi

line() { printf '%s\n' "----------------------------------------------------------------------------"; }
title() { line; printf '%s%s%s\n' "$BOLD" "$1" "$RESET"; line; }
info() { printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; }
err() { printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*"; }
die() { err "$*"; exit 1; }

trap 'err "Failed at line $LINENO: $BASH_COMMAND"; exit 1' ERR

usage() {
  cat <<'EOF'
Clawdbot Quickstart
Usage: clawdbot-quickstart [options]

Options:
  --non-interactive      Fail if input required
  --skip-auth            Skip GitHub authentication
  --auth-method METHOD   auto (default), device, token
  --token-file PATH      Read GitHub token from file
  --token-env VAR        Read GitHub token from env var
  --channels LIST        Comma-separated channels to add (whatsapp,telegram,discord)
  --no-channels          Skip channel setup
  --github-host HOST     GitHub host (default: github.com)
  --no-env               Do not write ~/.config/clawdbot/env
  -h, --help             Show help
EOF
}

NON_INTERACTIVE=0
SKIP_AUTH=0
AUTH_METHOD="auto"
TOKEN_FILE=""
TOKEN_FILE_USED=""
TOKEN_FILE_EXPLICIT=0
TOKEN_ENV=""
CHANNELS=""
NO_CHANNELS=0
NO_ENV=0
GH_HOST="github.com"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive|--yes)
      NON_INTERACTIVE=1
      shift
      ;;
    --skip-auth)
      SKIP_AUTH=1
      shift
      ;;
    --auth-method)
      [[ -n "${2:-}" ]] || die "Missing value for --auth-method"
      AUTH_METHOD="$2"
      shift 2
      ;;
    --token-file)
      [[ -n "${2:-}" ]] || die "Missing value for --token-file"
      TOKEN_FILE="$2"
      TOKEN_FILE_EXPLICIT=1
      shift 2
      ;;
    --token-env)
      [[ -n "${2:-}" ]] || die "Missing value for --token-env"
      TOKEN_ENV="$2"
      shift 2
      ;;
    --channels)
      [[ -n "${2:-}" ]] || die "Missing value for --channels"
      CHANNELS="$2"
      shift 2
      ;;
    --no-channels)
      NO_CHANNELS=1
      shift
      ;;
    --github-host)
      [[ -n "${2:-}" ]] || die "Missing value for --github-host"
      GH_HOST="$2"
      shift 2
      ;;
    --no-env)
      NO_ENV=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

case "$AUTH_METHOD" in
  auto|device|token) ;;
  *) die "Invalid --auth-method (use auto|device|token)" ;;
esac

GH_HOST="${GH_HOST#https://}"
GH_HOST="${GH_HOST#http://}"

require_cmd() {
  local cmd="$1"
  local message="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "$message"
  fi
}

confirm() {
  local prompt="$1"
  local default="${2:-Y}"
  local reply=""
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    return 1
  fi
  if [[ "$default" == "Y" ]]; then
    read -r -p "$prompt [Y/n] " reply || true
    reply="${reply:-Y}"
  else
    read -r -p "$prompt [y/N] " reply || true
    reply="${reply:-N}"
  fi
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

discover_token() {
  local token=""
  TOKEN_FILE_USED=""
  if [[ -n "$TOKEN_ENV" ]]; then
    token="${!TOKEN_ENV:-}"
  fi

  if [[ -z "$token" ]]; then
    local var=""
    for var in CLAWDBOT_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN; do
      if [[ -n "${!var:-}" ]]; then
        token="${!var}"
        break
      fi
    done
  fi

  if [[ -z "$token" ]]; then
    local file=""
    if [[ -n "$TOKEN_FILE" ]]; then
      file="$TOKEN_FILE"
    elif [[ -r "$HOME/.config/clawdbot/seed/github_token" ]]; then
      file="$HOME/.config/clawdbot/seed/github_token"
    elif [[ -r "/var/lib/clawdbot/secrets/github_token" ]]; then
      file="/var/lib/clawdbot/secrets/github_token"
    fi
    if [[ -n "$file" ]]; then
      TOKEN_FILE_USED="$file"
      token="$(<"$file")"
    fi
  fi

  token="${token//$'\r'/}"
  token="${token//$'\n'/}"
  printf '%s' "$token"
}

cleanup_token_file() {
  if [[ -n "$TOKEN_FILE_USED" && "$TOKEN_FILE_EXPLICIT" -eq 0 ]]; then
    if [[ -f "$TOKEN_FILE_USED" ]]; then
      rm -f "$TOKEN_FILE_USED" || true
      ok "Removed seed token file at $TOKEN_FILE_USED"
    fi
  fi
}

prompt_token() {
  local token=""
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    return 1
  fi
  printf '%s' "Paste GitHub token (input hidden): "
  read -r -s token || true
  printf '\n'
  token="${token//$'\r'/}"
  token="${token//$'\n'/}"
  printf '%s' "$token"
}

gh_is_authed() {
  gh auth status -h "$GH_HOST" >/dev/null 2>&1
}

gh_login_token() {
  local token="$1"
  [[ -n "$token" ]] || return 1
  info "Authenticating GitHub using a token"
  printf '%s' "$token" | gh auth login --hostname "$GH_HOST" --with-token
}

gh_login_device() {
  info "Starting GitHub device authentication"
  info "If this VM has no browser, open the URL from your local machine."
  gh auth login --hostname "$GH_HOST" --web
}

secure_gh_files() {
  if [[ -d "$HOME/.config/gh" ]]; then
    chmod 700 "$HOME/.config/gh" || true
  fi
  if [[ -f "$HOME/.config/gh/hosts.yml" ]]; then
    chmod 600 "$HOME/.config/gh/hosts.yml" || true
  fi
}

configure_copilot_env() {
  if [[ "$NO_ENV" -eq 1 ]]; then
    info "Skipping Copilot environment file"
    return 0
  fi

  local token
  token="$(gh auth token -h "$GH_HOST" 2>/dev/null || true)"
  if [[ -z "$token" ]]; then
    warn "Unable to read GitHub token for Copilot export"
    return 0
  fi

  local env_dir="$HOME/.config/clawdbot"
  local env_file="$env_dir/env"
  install -d -m 0700 "$env_dir"
  local old_umask
  old_umask="$(umask)"
  umask 077
  {
    printf 'export COPILOT_GITHUB_TOKEN=%s\n' "$token"
    printf 'export CLAWDBOT_GITHUB_HOST=%s\n' "$GH_HOST"
  } > "$env_file"
  umask "$old_umask"
  chmod 600 "$env_file"

  export COPILOT_GITHUB_TOKEN="$token"
  export CLAWDBOT_GITHUB_HOST="$GH_HOST"
  ok "Saved Copilot token to $env_file"

  if [[ -f "$HOME/.config/systemd/user/clawdbot-gateway.service" ]]; then
    local dropin_dir="$HOME/.config/systemd/user/clawdbot-gateway.service.d"
    install -d -m 0700 "$dropin_dir"
    cat > "$dropin_dir/10-copilot.conf" <<'EOF'
[Service]
EnvironmentFile=%h/.config/clawdbot/env
EOF
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user daemon-reload || true
      if systemctl --user is-active --quiet clawdbot-gateway.service; then
        systemctl --user restart clawdbot-gateway.service || true
      fi
    fi
    ok "Configured gateway service to load Copilot token"
  fi

  unset token
}

ensure_gh_auth() {
  if gh_is_authed; then
    ok "GitHub already authenticated for $GH_HOST"
    return 0
  fi

  local token=""
  local used_token=0
  case "$AUTH_METHOD" in
    auto)
      token="$(discover_token)"
      if [[ -n "$token" ]]; then
        if ! gh_login_token "$token"; then
          warn "Token authentication failed"
          token=""
        else
          used_token=1
        fi
      fi
      if [[ -z "$token" ]]; then
        if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
          warn "Non-interactive mode requires a token"
          return 1
        fi
        gh_login_device
      fi
      ;;
    token)
      token="$(discover_token)"
      if [[ -z "$token" ]]; then
        token="$(prompt_token || true)"
      fi
      if [[ -z "$token" ]]; then
        warn "No token provided"
        return 1
      fi
      if ! gh_login_token "$token"; then
        warn "Token authentication failed"
        return 1
      fi
      used_token=1
      ;;
    device)
      if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        warn "Device authentication requires interactive mode"
        return 1
      fi
      gh_login_device
      ;;
  esac

  if gh_is_authed; then
    if [[ "$used_token" -eq 1 ]]; then
      cleanup_token_file
    fi
    return 0
  fi
  return 1
}

setup_channels() {
  if [[ "$NO_CHANNELS" -eq 1 ]]; then
    info "Skipping channel setup"
    return 0
  fi

  local channels_input="$CHANNELS"
  if [[ -z "$channels_input" ]]; then
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
      return 0
    fi
    info "Optional: connect a messaging channel (whatsapp, telegram, discord)."
    read -r -p "Enter channels (comma-separated) or leave blank to skip: " channels_input || true
  fi

  channels_input="${channels_input// /}"
  if [[ -z "$channels_input" ]]; then
    info "No channels selected"
    return 0
  fi

  IFS=',' read -r -a channel_list <<< "$channels_input"
  local channel=""
  for channel in "${channel_list[@]}"; do
    [[ -n "$channel" ]] || continue
    info "Adding channel: $channel"
    if ! clawdbot channel add "$channel"; then
      warn "Failed to add $channel. You can retry with: clawdbot channel add $channel"
    fi
  done
}

mark_done() {
  local done_dir="$HOME/.config/clawdbot"
  install -d -m 0700 "$done_dir"
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$done_dir/quickstart.done"
}

main() {
  title "Clawdbot Quickstart"
  info "This setup takes about 3-5 minutes."
  info "GitHub host: $GH_HOST"

  require_cmd "clawdbot" "Clawdbot CLI not found. Run: sudo /opt/clawdbot/scripts/setup.sh"
  require_cmd "gh" "GitHub CLI not found. Run: sudo /opt/clawdbot/scripts/setup.sh"
  require_cmd "curl" "curl is required."

  if ! curl -fsSL "https://$GH_HOST" >/dev/null 2>&1; then
    warn "Unable to reach $GH_HOST. Authentication may fail."
  fi

  if [[ "$SKIP_AUTH" -eq 1 ]]; then
    warn "Skipping GitHub authentication. Copilot features may be unavailable."
  else
    info "Authenticating GitHub Copilot"
    if ! ensure_gh_auth; then
      warn "GitHub authentication not completed."
      if confirm "Continue without Copilot authentication?" "N"; then
        SKIP_AUTH=1
      else
        die "Authentication required. Re-run: clawdbot-quickstart"
      fi
    else
      secure_gh_files
      configure_copilot_env
    fi
  fi

  setup_channels

  mark_done

  line
  ok "Quickstart complete"
  if [[ "$SKIP_AUTH" -eq 1 ]]; then
    warn "Copilot authentication was skipped. Run: gh auth login --web"
  fi
  info "Try: clawdbot agent \"hello world\""
  info "Add channels later with: clawdbot channel add <whatsapp|telegram|discord>"
  info "Re-run anytime: clawdbot-quickstart"
}

main
