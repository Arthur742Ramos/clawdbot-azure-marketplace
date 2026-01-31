#!/usr/bin/env bash
# clawdbot-quickstart - Thin wrapper for clawdbot onboard
# This exists for backwards compatibility. The real wizard is: clawdbot onboard

set -Eeuo pipefail

if ! command -v clawdbot >/dev/null 2>&1; then
  echo "Error: clawdbot is not installed." >&2
  exit 1
fi

exec clawdbot onboard "$@"
