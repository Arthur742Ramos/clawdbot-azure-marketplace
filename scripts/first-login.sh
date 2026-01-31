#!/usr/bin/env bash
set -u

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

DONE_FILE="$HOME/.config/clawdbot/quickstart.done"
SKIP_FILE="$HOME/.config/clawdbot/quickstart.skipped"

if [[ -f "$DONE_FILE" || -f "$SKIP_FILE" ]]; then
  exit 0
fi

if ! command -v clawdbot-quickstart >/dev/null 2>&1; then
  printf '%s\n' "Clawdbot quickstart is not installed. Run: sudo /opt/clawdbot/scripts/setup.sh"
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
    install -d -m 0700 "$HOME/.config/clawdbot"
    touch "$SKIP_FILE"
    printf '%s\n' "You can run it later with: clawdbot-quickstart"
    ;;
esac
