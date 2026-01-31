#!/usr/bin/env bash
# set-default-model.sh - Update Clawdbot config to use GPT-5.2-codex as primary

set -Eeuo pipefail

CONFIG_FILE="${HOME}/.clawdbot/clawdbot.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "No config file found at $CONFIG_FILE"
  exit 0
fi

# Backup config
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

# Use jq to update the primary model
if command -v jq >/dev/null 2>&1; then
  jq '.agents.defaults.model.primary = "github-copilot/gpt-5.2-codex" |
      .agents.defaults.model.fallbacks = ["github-copilot/claude-sonnet-4.5", "github-copilot/claude-sonnet-4"]' \
    "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  echo "Updated primary model to gpt-5.2-codex"
else
  echo "jq not available, skipping model update"
fi
