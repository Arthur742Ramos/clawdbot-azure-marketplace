#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  exit 0
fi

if [[ "$-" != *i* ]]; then
  exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  exit 0
fi

if [[ "${CLAWDBOT_SKIP_FIRST_LOGIN:-}" == "1" ]]; then
  exit 0
fi

CONFIG_DIR="$HOME/.config/clawdbot"
DONE_FILE="$CONFIG_DIR/quickstart.done"
PROMPTED_FILE="$CONFIG_DIR/first-login.done"

if [[ -f "$DONE_FILE" || -f "$PROMPTED_FILE" ]]; then
  exit 0
fi

on_interrupt() {
  printf '%s\n' "Cancelled. Run later with: clawdbot-quickstart"
  exit 130
}

trap on_interrupt INT TERM

if ! command -v clawdbot-quickstart >/dev/null 2>&1; then
  printf '%s\n' "Clawdbot quickstart is not installed. Run: sudo /usr/local/bin/clawdbot-setup"
  install -d -m 0700 "$CONFIG_DIR"
  touch "$PROMPTED_FILE"
  exit 0
fi

printf '\n'
printf '%s\n' "Welcome to Clawdbot."
printf '%s\n' "Run 'clawdbot-quickstart' to authenticate GitHub Copilot and connect channels."
read -r -p "Start now? [Y/n] " reply
reply="${reply:-Y}"

case "$reply" in
  y|Y|yes|YES)
    clawdbot-quickstart || true
    ;;
  *)
    printf '%s\n' "You can run it later with: clawdbot-quickstart"
    ;;
esac

install -d -m 0700 "$CONFIG_DIR"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$PROMPTED_FILE"
