#!/bin/bash
# Reads DISCORD_WEBHOOK_URL from environment (sourced from ~/.bounty-env)

if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
    echo "[discord-notify] DISCORD_WEBHOOK_URL not set — skipping" >&2
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
echo "$INPUT" | python3 "$SCRIPT_DIR/discord_notify.py" "$DISCORD_WEBHOOK_URL"
