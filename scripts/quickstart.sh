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

IS_TTY=0
if [[ -t 0 && -t 1 ]]; then
  IS_TTY=1
fi

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

usage() {
  cat <<'USAGE'
Clawdbot Quickstart
Usage: clawdbot-quickstart [options]

Options:
  --non-interactive       Fail if input is required
  --skip-auth             Skip GitHub authentication
  --auth-method METHOD    auto (default), device, token
  --token-file PATH       Read GitHub token from file
  --token-env VAR         Read GitHub token from env var
  --channels LIST         Comma-separated channels (whatsapp,telegram,discord)
  --no-channels           Skip channel setup
  --github-host HOST      GitHub host (default: github.com)
  --no-env                Do not write ~/.config/clawdbot/env
  -h, --help              Show help
USAGE
}

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
      [[ -n "${2:-}" ]] || { printf '%s\n' "Missing value for --auth-method" >&2; exit 1; }
      AUTH_METHOD="$2"
      shift 2
      ;;
    --token-file)
      [[ -n "${2:-}" ]] || { printf '%s\n' "Missing value for --token-file" >&2; exit 1; }
      TOKEN_FILE="$2"
      TOKEN_FILE_EXPLICIT=1
      shift 2
      ;;
    --token-env)
      [[ -n "${2:-}" ]] || { printf '%s\n' "Missing value for --token-env" >&2; exit 1; }
      TOKEN_ENV="$2"
      shift 2
      ;;
    --channels)
      [[ -n "${2:-}" ]] || { printf '%s\n' "Missing value for --channels" >&2; exit 1; }
      CHANNELS="$2"
      shift 2
      ;;
    --no-channels)
      NO_CHANNELS=1
      shift
      ;;
    --github-host)
      [[ -n "${2:-}" ]] || { printf '%s\n' "Missing value for --github-host" >&2; exit 1; }
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
      printf '%s\n' "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

case "$AUTH_METHOD" in
  auto|device|token) ;;
  *) printf '%s\n' "Invalid --auth-method (use auto|device|token)" >&2; exit 1 ;;
esac

GH_HOST="${GH_HOST#https://}"
GH_HOST="${GH_HOST#http://}"
GH_HOST="${GH_HOST%/}"

if [[ "$IS_TTY" -eq 0 ]]; then
  NON_INTERACTIVE=1
fi

if [[ "$NON_INTERACTIVE" -eq 1 && -z "$CHANNELS" ]]; then
  NO_CHANNELS=1
fi

if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
  export GH_PROMPT_DISABLED=1
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
err() { printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2; }

die() { err "$*"; exit 1; }

TMP_DIR=""
CURRENT_PID=""
CANCELLED=0

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

on_interrupt() {
  CANCELLED=1
  if [[ -n "$CURRENT_PID" ]]; then
    kill "$CURRENT_PID" 2>/dev/null || true
  fi
  err "Cancelled by user."
  exit 130
}

on_error() {
  local exit_code=$?
  if [[ "$CANCELLED" -eq 1 ]]; then
    exit "$exit_code"
  fi
  err "Failed at line $LINENO: $BASH_COMMAND"
  exit "$exit_code"
}

trap cleanup EXIT
trap on_interrupt INT TERM
trap on_error ERR

TMP_DIR="$(mktemp -d)"

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

run_step() {
  local label="$1"
  shift
  local log_file
  log_file="$(mktemp "$TMP_DIR/step.XXXXXX")"

  if [[ "$IS_TTY" -eq 1 && "$NON_INTERACTIVE" -eq 0 ]]; then
    printf '%s ' "$label"
    "$@" >"$log_file" 2>&1 &
    CURRENT_PID=$!
    local spin='|/-\\'
    local i=0
    while kill -0 "$CURRENT_PID" 2>/dev/null; do
      printf '\b%s' "${spin:i%4:1}"
      sleep 0.1
      i=$((i + 1))
    done
    wait "$CURRENT_PID"
    local status=$?
    CURRENT_PID=""
    if [[ "$status" -eq 0 ]]; then
      printf '\b%s\n' "${GREEN}ok${RESET}"
      rm -f "$log_file"
      return 0
    fi
    printf '\b%s\n' "${RED}failed${RESET}"
    if [[ -s "$log_file" ]]; then
      warn "Command output:"
      while IFS= read -r line; do
        printf '  %s\n' "$line" >&2
      done < "$log_file"
    fi
    rm -f "$log_file"
    return "$status"
  fi

  info "$label"
  "$@"
}

with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

curl_check() {
  local url="$1"
  curl -fsSL --retry 3 --retry-connrefused --connect-timeout 5 --max-time 15 "$url" >/dev/null 2>&1
}

warn_if_weak_permissions() {
  local file="$1"
  local perms=""
  if perms="$(stat -c %a "$file" 2>/dev/null)"; then
    if [[ "$perms" -gt 600 ]]; then
      warn "Token file $file is not 600; recommend chmod 600 $file"
    fi
  fi
}

discover_token() {
  local token=""
  TOKEN_FILE_USED=""

  if [[ -n "$TOKEN_ENV" ]]; then
    token="${!TOKEN_ENV:-}"
  fi

  if [[ -z "$token" ]]; then
    local var=""
    for var in CLAWDBOT_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN COPILOT_GITHUB_TOKEN; do
      if [[ -n "${!var:-}" ]]; then
        token="${!var}"
        break
      fi
    done
  fi

  if [[ -z "$token" ]]; then
    local file=""
    if [[ -n "$TOKEN_FILE" ]]; then
      if [[ ! -r "$TOKEN_FILE" ]]; then
        die "Token file not readable: $TOKEN_FILE"
      fi
      file="$TOKEN_FILE"
    elif [[ -r "$HOME/.config/clawdbot/seed/github_token" ]]; then
      file="$HOME/.config/clawdbot/seed/github_token"
    elif [[ -r "/var/lib/clawdbot/secrets/github_token" ]]; then
      file="/var/lib/clawdbot/secrets/github_token"
    fi
    if [[ -n "$file" ]]; then
      TOKEN_FILE_USED="$file"
      warn_if_weak_permissions "$file"
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
  local token_file="$TMP_DIR/gh-token"
  printf '%s' "$token" > "$token_file"
  chmod 600 "$token_file"
  if ! run_step "Authenticating with GitHub (token)" env GH_HOST="$GH_HOST" \
    bash -c 'gh auth login --hostname "$GH_HOST" --with-token < "$1"' _ "$token_file"; then
    rm -f "$token_file"
    return 1
  fi
  rm -f "$token_file"
}

gh_login_device() {
  info "Starting GitHub device authentication"
  info "If this VM has no browser, open the URL shown in your local browser."
  info "Press Ctrl+C to cancel."
  if ! gh auth login --hostname "$GH_HOST" --web; then
    return 1
  fi
}

gh_auth_valid() {
  local token
  token="$(gh auth token -h "$GH_HOST" 2>/dev/null || true)"
  if [[ -z "$token" ]]; then
    return 1
  fi
  with_timeout 20 gh api --hostname "$GH_HOST" -H "Accept: application/vnd.github+json" /user >/dev/null 2>&1 || return 1
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

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user cat clawdbot-gateway.service >/dev/null 2>&1; then
      local dropin_dir="$HOME/.config/systemd/user/clawdbot-gateway.service.d"
      install -d -m 0700 "$dropin_dir"
      cat > "$dropin_dir/10-copilot.conf" <<'EOF'
[Service]
EnvironmentFile=%h/.config/clawdbot/env
EOF
      systemctl --user daemon-reload || true
      systemctl --user enable --now clawdbot-gateway.service >/dev/null 2>&1 || true
      if systemctl --user is-active --quiet clawdbot-gateway.service; then
        systemctl --user restart clawdbot-gateway.service || true
      fi
      ok "Configured gateway service to load Copilot token"
    fi
  fi

  unset token
}

ensure_gh_auth() {
  if gh_is_authed; then
    if gh_auth_valid; then
      ok "GitHub already authenticated for $GH_HOST"
      return 0
    fi
    warn "GitHub auth exists but could not be validated. Re-authentication may be required."
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
          warn "Non-interactive mode requires a token."
          return 1
        fi
        if ! gh_login_device; then
          return 1
        fi
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
      if ! gh_login_device; then
        return 1
      fi
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

COPILOT_ERROR=""
validate_copilot_subscription() {
  local output=""
  output="$(with_timeout 20 gh api --hostname "$GH_HOST" -X POST /copilot_internal/v2/token 2>&1)" || {
    COPILOT_ERROR="$output"
    case "$output" in
      *copilot*|*Copilot*|*COPILOT*) return 2 ;;
      *) return 1 ;;
    esac
  }

  local token
  if ! token="$(printf '%s' "$output" | jq -r '.token // empty' 2>/dev/null)"; then
    COPILOT_ERROR="Unable to parse Copilot response"
    return 1
  fi
  if [[ -z "$token" || "$token" == "null" ]]; then
    COPILOT_ERROR="Copilot token missing"
    return 2
  fi

  return 0
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
    case "$channel" in
      whatsapp|telegram|discord) ;;
      *) warn "Unknown channel '$channel' (skipping)"; continue ;;
    esac
    info "Adding channel: $channel"
    if ! clawdbot channel add "$channel"; then
      warn "Failed to add $channel. Retry with: clawdbot channel add $channel"
    fi
  done
}

mark_done() {
  local status="$1"
  local done_dir="$HOME/.config/clawdbot"
  install -d -m 0700 "$done_dir"
  {
    printf 'status=%s\n' "$status"
    printf 'timestamp=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "$done_dir/quickstart.done"
}

main() {
  title "Clawdbot Quickstart"
  info "This setup takes about 3-5 minutes."
  info "GitHub host: $GH_HOST"
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    info "Running in non-interactive mode."
  fi

  require_cmd "clawdbot" "Clawdbot CLI not found. Run: sudo /usr/local/bin/clawdbot-setup"
  require_cmd "gh" "GitHub CLI not found. Run: sudo /usr/local/bin/clawdbot-setup"
  require_cmd "curl" "curl is required."
  require_cmd "jq" "jq is required. Run: sudo /usr/local/bin/clawdbot-setup"

  if ! curl_check "https://$GH_HOST"; then
    warn "Unable to reach $GH_HOST. Authentication may fail."
  fi

  if [[ "$GH_HOST" == "github.com" ]]; then
    if ! curl_check "https://api.github.com"; then
      warn "Unable to reach api.github.com. Authentication may fail."
    fi
  else
    if ! curl_check "https://$GH_HOST/api/v3"; then
      warn "Unable to reach $GH_HOST/api/v3. Authentication may fail."
    fi
  fi

  if [[ "$SKIP_AUTH" -eq 1 ]]; then
    warn "Skipping GitHub authentication."
  else
    info "Authenticating with GitHub"
    info "This enables: gh CLI, GitHub Copilot (if subscribed), and coding agents"
    if ! ensure_gh_auth; then
      warn "GitHub authentication not completed."
      if confirm "Continue without GitHub authentication?" "Y"; then
        SKIP_AUTH=1
      else
        die "Authentication required. Re-run: clawdbot-quickstart (or use --skip-auth)"
      fi
    else
      secure_gh_files
      if validate_copilot_subscription; then
        ok "Copilot subscription validated"
        configure_copilot_env
      else
        case "$?" in
          2)
            info "No Copilot subscription detected (optional - you can use API keys instead)"
            ;;
          *)
            info "Could not validate Copilot subscription (optional)"
            ;;
        esac
        if [[ -n "$COPILOT_ERROR" ]]; then
          warn "$COPILOT_ERROR"
        fi
        info "You can configure LLM providers later with: clawdbot configure --section model"
        SKIP_AUTH=1
      fi
    fi
  fi

  setup_channels

  if [[ "$SKIP_AUTH" -eq 1 ]]; then
    mark_done "partial"
  else
    mark_done "complete"
  fi

  line
  ok "Quickstart complete"
  ok "You're all set. Enjoy Clawdbot!"
  if [[ "$SKIP_AUTH" -eq 1 ]]; then
    info "Configure LLM: clawdbot configure --section model"
    info "Or set API keys: ANTHROPIC_API_KEY, OPENAI_API_KEY, etc."
  else
    ok "GitHub Copilot is ready"
  fi

  if command -v opencode >/dev/null 2>&1; then
    info "OpenCode needs a PTY. Use: ssh -tt <user>@<host>"
  fi

  if command -v loginctl >/dev/null 2>&1; then
    info "Keep the gateway running after logout: sudo loginctl enable-linger $USER"
  fi

  info "Try: clawdbot agent \"hello world\""
  info "Add channels later with: clawdbot channel add <whatsapp|telegram|discord>"
  info "Re-run anytime: clawdbot-quickstart"
}

# Test: clawdbot-quickstart --non-interactive --auth-method token --no-channels
# Test: CLAWDBOT_GITHUB_TOKEN=ghp_xxx clawdbot-quickstart --non-interactive --no-channels

main
