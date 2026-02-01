#!/usr/bin/env bash
# openclaw-quickstart - Thin wrapper for openclaw onboard
# This exists for backwards compatibility. The real wizard is: openclaw onboard

set -Eeuo pipefail

if ! command -v openclaw >/dev/null 2>&1; then
  echo "Error: openclaw is not installed." >&2
  exit 1
fi

exec openclaw onboard "$@"
