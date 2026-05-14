#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# launch-bounty.sh — tmux session for Claude Code bug bounty work
#
# Layout:
#   Window 0 "claude"     → sources env, cds to project, runs claude
#   Window 1 "workspace"  → sources env, cds to project, ready for your work
#   Window 2 "monitor"    → htop + watch for recon output
#
# Usage:
#   ~/launch-bounty.sh
#   tmux attach -t bounty   (re-attach)
# ─────────────────────────────────────────────────────────────────────────────

SESSION="bounty"
WORKDIR="WORKDIR_PLACEHOLDER"  # replaced by install.sh

# Source secrets so Claude Code picks up ANTHROPIC_API_KEY
[[ -f "$HOME/.bounty-env" ]] && source "$HOME/.bounty-env"

# Kill existing session
tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION"

# ── Window 0: claude ──────────────────────────────────────────────────────────
tmux new-session -d -s "$SESSION" -n "claude" -x 220 -y 50
tmux send-keys -t "$SESSION:claude" "source ~/.bashrc && source ~/.bounty-env && cd $WORKDIR && claude" Enter

# ── Window 1: workspace ───────────────────────────────────────────────────────
tmux new-window -t "$SESSION" -n "workspace"
tmux send-keys -t "$SESSION:workspace" "source ~/.bashrc && source ~/.bounty-env && cd $WORKDIR" Enter
tmux send-keys -t "$SESSION:workspace" "echo '  workspace ready — Ctrl+b 0 for Claude, Ctrl+b 2 for monitor'" Enter

# ── Window 2: monitor ─────────────────────────────────────────────────────────
tmux new-window -t "$SESSION" -n "monitor"
tmux send-keys -t "$SESSION:monitor" "htop" Enter

# ── Focus Claude ──────────────────────────────────────────────────────────────
tmux select-window -t "$SESSION:claude"
tmux attach-session -t "$SESSION"
