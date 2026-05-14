#!/bin/bash
# Reads DISCORD_WEBHOOK_URL from environment (set in ~/.bounty-env)
# Never hardcode the webhook here — it lives in ~/.bounty-env which is gitignored

if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
    echo "[discord-notify] DISCORD_WEBHOOK_URL not set — skipping notification" >&2
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
echo "$INPUT" | python3 "$SCRIPT_DIR/discord_notify.py" "$DISCORD_WEBHOOK_URL"
