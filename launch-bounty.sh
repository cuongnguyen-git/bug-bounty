#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# launch-bounty.sh — start or re-attach the bug bounty tmux session
#
# Windows:
#   0 claude     → runs claude in ~/bug-bounty
#   1 workspace  → shell in ~/bug-bounty for manual commands
#   2 monitor    → htop
#
# Re-attach: tmux attach -t bounty
# ─────────────────────────────────────────────────────────────────────────────

SESSION="bounty"
WORKDIR="$HOME/bug-bounty"

# Load secrets so Claude Code picks up DISCORD_WEBHOOK_URL
[[ -f "$HOME/.bounty-env" ]] && source "$HOME/.bounty-env"

# If session already exists just re-attach
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' already running — re-attaching..."
    tmux attach-session -t "$SESSION"
    exit 0
fi

# ── Window 0: claude ──────────────────────────────────────────────────────────
tmux new-session -d -s "$SESSION" -n "claude" -x 220 -y 50
tmux send-keys -t "$SESSION:claude" \
    "source ~/.bashrc && cd $WORKDIR && claude" Enter

# ── Window 1: workspace ───────────────────────────────────────────────────────
tmux new-window -t "$SESSION" -n "workspace"
tmux send-keys -t "$SESSION:workspace" \
    "source ~/.bashrc && cd $WORKDIR" Enter

# ── Window 2: monitor ─────────────────────────────────────────────────────────
tmux new-window -t "$SESSION" -n "monitor"
tmux send-keys -t "$SESSION:monitor" "htop" Enter

# ── Focus claude window and attach ────────────────────────────────────────────
tmux select-window -t "$SESSION:claude"
tmux attach-session -t "$SESSION"
