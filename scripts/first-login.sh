#!/usr/bin/env bash
set -Eeuo pipefail

# Skip if root
if [[ "${EUID}" -eq 0 ]]; then
  exit 0
fi

# Skip if non-interactive
if [[ "$-" != *i* ]]; then
  exit 0
fi

# Skip if no TTY
if [[ ! -t 0 || ! -t 1 ]]; then
  exit 0
fi

# Skip if disabled
if [[ "${OPENCLAW_SKIP_FIRST_LOGIN:-}" == "1" ]]; then
  exit 0
fi

CONFIG_DIR="$HOME/.openclaw"
PROMPTED_FILE="$CONFIG_DIR/.first-login.done"

# Skip if already prompted
if [[ -f "$PROMPTED_FILE" || -f "$CONFIG_DIR/openclaw.json" ]]; then
  exit 0
fi

on_interrupt() {
  printf '%s\n' "Cancelled. Run later with: openclaw onboard"
  exit 130
}

trap on_interrupt INT TERM

if ! command -v openclaw >/dev/null 2>&1; then
  printf '%s\n' "Openclaw is not installed."
  install -d -m 0700 "$CONFIG_DIR"
  touch "$PROMPTED_FILE"
  exit 0
fi

printf '\n'
printf '%s\n' "Welcome to Openclaw!"
printf '%s\n' "Run 'openclaw onboard' to configure your LLM provider and start the gateway."
printf '\n'
read -r -p "Start onboarding now? [Y/n] " reply
reply="${reply:-Y}"

case "$reply" in
  y|Y|yes|YES)
    openclaw onboard || true
    ;;
  *)
    printf '%s\n' "You can run it later with: openclaw onboard"
    ;;
esac

install -d -m 0700 "$CONFIG_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$PROMPTED_FILE"
