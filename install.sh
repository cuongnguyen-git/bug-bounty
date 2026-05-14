#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — Bug Bounty VPS bootstrap
# Usage: git clone <repo> && cd <repo> && chmod +x install.sh && ./install.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$HOME/bug-bounty"
KNOWLEDGE_DIR="$HOME/bug-bounty/knowledge"
ENV_FILE="$HOME/.bounty-env"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Bug Bounty VPS Installer             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Discord webhook ────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
    warn ".bounty-env already exists — skipping. Edit $ENV_FILE to update."
    source "$ENV_FILE"
else
    echo -e "${YELLOW}Paste your Discord webhook URL:${NC}"
    read -r DISCORD_WEBHOOK_URL
    echo ""
    [[ -z "$DISCORD_WEBHOOK_URL" ]] && error "Webhook cannot be empty"

    cat > "$ENV_FILE" <<EOF
# Bug bounty secrets — DO NOT COMMIT
export DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL"
EOF
    chmod 600 "$ENV_FILE"
    success "Saved $ENV_FILE (chmod 600)"
fi

source "$ENV_FILE"

if ! grep -q "bounty-env" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# Bug bounty" >> "$HOME/.bashrc"
    echo '[[ -f $HOME/.bounty-env ]] && source $HOME/.bounty-env' >> "$HOME/.bashrc"
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> "$HOME/.bashrc"
    success "Updated .bashrc"
fi

# ── 2. System packages ────────────────────────────────────────────────────────
info "Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    tmux curl wget git unzip jq python3 python3-pip \
    nmap dnsutils whois net-tools build-essential \
    libssl-dev libffi-dev python3-dev
success "System packages ready"

# ── 3. Go ─────────────────────────────────────────────────────────────────────
info "Checking Go..."
if ! command -v go &>/dev/null; then
    GO_VERSION="1.22.3"
    info "Installing Go $GO_VERSION..."
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    success "Go installed"
else
    success "Go already installed: $(go version)"
fi

export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
mkdir -p "$HOME/go/bin"

# ── 4. Node.js + Claude Code ──────────────────────────────────────────────────
info "Checking Node.js..."
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - -q
    sudo apt-get install -y -qq nodejs
    success "Node.js installed: $(node --version)"
else
    success "Node.js: $(node --version)"
fi

info "Installing Claude Code..."
sudo npm install -g @anthropic-ai/claude-code --quiet
success "Claude Code installed"

# ── 5. Go recon tools ─────────────────────────────────────────────────────────
info "Installing Go recon tools..."

GO_TOOLS=(
    "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    "github.com/projectdiscovery/httpx/cmd/httpx@latest"
    "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    "github.com/projectdiscovery/katana/cmd/katana@latest"
    "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    "github.com/tomnomnom/waybackurls@latest"
    "github.com/tomnomnom/gf@latest"
    "github.com/tomnomnom/anew@latest"
    "github.com/lc/gau/v2/cmd/gau@latest"
    "github.com/hakluke/hakrawler@latest"
    "github.com/ffuf/ffuf/v2@latest"
)

for tool in "${GO_TOOLS[@]}"; do
    tool_name=$(basename "${tool%%@*}")
    if command -v "$tool_name" &>/dev/null; then
        warn "  $tool_name already installed — skipping"
    else
        info "  Installing $tool_name..."
        go install "$tool" 2>/dev/null \
            && success "  $tool_name ✓" \
            || warn "  $tool_name failed — install manually later"
    fi
done

# ── 6. Python recon tools ─────────────────────────────────────────────────────
info "Installing Python tools..."
pip3 install -q --break-system-packages arjun 2>/dev/null || true
success "Python tools ready"

# ── 7. Wordlists ──────────────────────────────────────────────────────────────
info "Setting up wordlists..."
mkdir -p "$HOME/wordlists"

if [[ ! -d "$HOME/wordlists/SecLists" ]]; then
    info "Cloning SecLists (shallow — this takes a minute)..."
    git clone -q --depth 1 https://github.com/danielmiessler/SecLists.git "$HOME/wordlists/SecLists"
    success "SecLists ready"
else
    success "SecLists already present"
fi

# ── 8. Deploy project files ───────────────────────────────────────────────────
info "Deploying to $WORKDIR..."
mkdir -p "$WORKDIR/.claude/hooks"
mkdir -p "$WORKDIR/.claude/skills"
mkdir -p "$KNOWLEDGE_DIR"

# CLAUDE.md
cp "$REPO_DIR/CLAUDE.md" "$WORKDIR/CLAUDE.md"
success "CLAUDE.md → $WORKDIR/CLAUDE.md"

# settings.json — stamp in real hook paths
sed "s|HOME_PLACEHOLDER|$HOME|g" \
    "$REPO_DIR/.claude/settings.json.template" > "$WORKDIR/.claude/settings.json"
success "settings.json → $WORKDIR/.claude/settings.json"

# Hooks
cp "$REPO_DIR/.claude/hooks/discord-notify.sh" "$WORKDIR/.claude/hooks/"
cp "$REPO_DIR/.claude/hooks/discord_notify.py"  "$WORKDIR/.claude/hooks/"
chmod +x "$WORKDIR/.claude/hooks/discord-notify.sh"
success "Hooks deployed"

# Skills (if any are checked in)
if [[ -d "$REPO_DIR/.claude/skills" ]] && [[ "$(ls -A "$REPO_DIR/.claude/skills" 2>/dev/null)" ]]; then
    cp -r "$REPO_DIR/.claude/skills/." "$WORKDIR/.claude/skills/"
    success "Skills deployed"
fi

# Knowledge base stubs
for f in weak-patterns.md recon-noise.md winning-patterns.md target-notes.md; do
    if [[ ! -f "$KNOWLEDGE_DIR/$f" ]]; then
        printf "# %s\n_Populated by Claude over time._\n" "$f" > "$KNOWLEDGE_DIR/$f"
    fi
done
success "Knowledge base ready at $KNOWLEDGE_DIR"

# Launch script
cp "$REPO_DIR/launch-bounty.sh" "$HOME/launch-bounty.sh"
chmod +x "$HOME/launch-bounty.sh"
success "launch-bounty.sh → ~/launch-bounty.sh"

# ── 9. Nuclei templates ───────────────────────────────────────────────────────
info "Updating nuclei templates..."
"$HOME/go/bin/nuclei" -update-templates -silent 2>/dev/null || true
success "Nuclei templates updated"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Installation complete! ✓          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${YELLOW}Next: authenticate Claude Code${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Run:  ${CYAN}~/launch-bounty.sh${NC}"
echo -e "  ${CYAN}2.${NC} In the claude window, Claude Code will print a login URL"
echo -e "  ${CYAN}3.${NC} Open that URL in your local browser (where you're logged into Claude Max)"
echo -e "  ${CYAN}4.${NC} Approve — done. Token saved, never needed again."
echo ""
echo -e "  Working dir:    ${CYAN}$WORKDIR${NC}"
echo -e "  Knowledge base: ${CYAN}$KNOWLEDGE_DIR${NC}"
echo -e "  Re-attach tmux: ${CYAN}tmux attach -t bounty${NC}"
echo ""
