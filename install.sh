#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — Bug Bounty VPS bootstrap
# Usage: git clone <repo> && cd bugbounty-setup && ./install.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$HOME/claude-bounty"
KNOWLEDGE_DIR="$HOME/bugbounty/knowledge"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Bug Bounty VPS Installer             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Secrets ────────────────────────────────────────────────────────────────
info "Configuring secrets..."

ENV_FILE="$HOME/.bounty-env"

if [[ -f "$ENV_FILE" ]]; then
    warn ".bounty-env already exists — skipping secret prompts. Edit $ENV_FILE to update."
    source "$ENV_FILE"
else
    # Discord webhook (only secret needed — Claude Max uses OAuth, not API key)
    echo ""
    echo -e "${YELLOW}Paste your Discord webhook URL:${NC}"
    read -r DISCORD_WEBHOOK_URL
    echo ""
    [[ -z "$DISCORD_WEBHOOK_URL" ]] && error "Discord webhook cannot be empty"

    cat > "$ENV_FILE" <<EOF
# Bug bounty environment — DO NOT COMMIT THIS FILE
export DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK_URL"
EOF
    chmod 600 "$ENV_FILE"
    success "Secrets saved to $ENV_FILE (mode 600, not committed)"
fi

# Source into current shell
source "$ENV_FILE"

# Add to .bashrc if not already there
if ! grep -q "bounty-env" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# Bug bounty env" >> "$HOME/.bashrc"
    echo "[[ -f \$HOME/.bounty-env ]] && source \$HOME/.bounty-env" >> "$HOME/.bashrc"
    success "Added .bounty-env sourcing to .bashrc"
fi

# ── 2. System packages ────────────────────────────────────────────────────────
info "Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    tmux curl wget git unzip jq python3 python3-pip \
    nmap dnsutils whois net-tools build-essential \
    libssl-dev libffi-dev python3-dev
success "System packages installed"

# ── 3. Go ─────────────────────────────────────────────────────────────────────
info "Checking Go..."
if ! command -v go &>/dev/null; then
    GO_VERSION="1.22.3"
    info "Installing Go $GO_VERSION..."
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> "$HOME/.bashrc"
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    success "Go $GO_VERSION installed"
else
    success "Go already installed: $(go version)"
fi

export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
mkdir -p "$HOME/go/bin"

# ── 4. Node + Claude Code ─────────────────────────────────────────────────────
info "Checking Node.js..."
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - -q
    sudo apt-get install -y -qq nodejs
    success "Node.js installed: $(node --version)"
else
    success "Node.js already installed: $(node --version)"
fi

info "Installing Claude Code..."
sudo npm install -g @anthropic-ai/claude-code --quiet
success "Claude Code installed: $(claude --version 2>/dev/null || echo 'installed')"

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
    "github.com/KathanP19/Jsluice@latest"
    "github.com/ffuf/ffuf/v2@latest"
)

for tool in "${GO_TOOLS[@]}"; do
    tool_name=$(basename "${tool%%@*}")
    if command -v "$tool_name" &>/dev/null; then
        warn "$tool_name already installed — skipping"
    else
        info "  Installing $tool_name..."
        go install "$tool" 2>/dev/null && success "  $tool_name ✓" || warn "  $tool_name failed — check manually"
    fi
done

# ── 6. Python recon tools ─────────────────────────────────────────────────────
info "Installing Python recon tools..."
pip3 install -q --break-system-packages \
    trufflehog \
    arjun \
    sqlmap 2>/dev/null || true
success "Python tools installed"

# ── 7. Wordlists ──────────────────────────────────────────────────────────────
info "Setting up wordlists..."
WORDLIST_DIR="$HOME/wordlists"
mkdir -p "$WORDLIST_DIR"

if [[ ! -f "$WORDLIST_DIR/SecLists/.git/config" ]]; then
    info "Cloning SecLists (this may take a moment)..."
    git clone -q --depth 1 https://github.com/danielmiessler/SecLists.git "$WORDLIST_DIR/SecLists"
    success "SecLists downloaded"
else
    success "SecLists already present"
fi

# ── 8. Deploy project files ───────────────────────────────────────────────────
info "Deploying project files to $WORKDIR..."
mkdir -p "$WORKDIR/.claude/hooks"
mkdir -p "$WORKDIR/.claude/skills"
mkdir -p "$KNOWLEDGE_DIR"

# CLAUDE.md
cp "$REPO_DIR/CLAUDE.md" "$WORKDIR/CLAUDE.md"
success "CLAUDE.md deployed"

# settings.json — inject real webhook URL
sed "s|DISCORD_WEBHOOK_PLACEHOLDER|$DISCORD_WEBHOOK_URL|g" \
    "$REPO_DIR/.claude/settings.json.template" > "$WORKDIR/.claude/settings.json"
success "settings.json deployed"

# Hooks
cp "$REPO_DIR/.claude/hooks/discord-notify.sh" "$WORKDIR/.claude/hooks/"
cp "$REPO_DIR/.claude/hooks/discord_notify.py" "$WORKDIR/.claude/hooks/"
chmod +x "$WORKDIR/.claude/hooks/discord-notify.sh"
success "Discord hooks deployed"

# Skills
if [[ -d "$REPO_DIR/.claude/skills" ]] && [[ "$(ls -A "$REPO_DIR/.claude/skills")" ]]; then
    cp -r "$REPO_DIR/.claude/skills/." "$WORKDIR/.claude/skills/"
    success "Skills deployed"
fi

# Launch script
cp "$REPO_DIR/launch-bounty.sh" "$HOME/launch-bounty.sh"
sed -i "s|WORKDIR_PLACEHOLDER|$WORKDIR|g" "$HOME/launch-bounty.sh"
chmod +x "$HOME/launch-bounty.sh"
success "launch-bounty.sh deployed to ~/"

# Knowledge base stubs (don't overwrite if they exist)
for f in weak-patterns.md recon-noise.md winning-patterns.md target-notes.md; do
    if [[ ! -f "$KNOWLEDGE_DIR/$f" ]]; then
        echo "# $f" > "$KNOWLEDGE_DIR/$f"
        echo "_Auto-created by installer. Claude will populate this over time._" >> "$KNOWLEDGE_DIR/$f"
    fi
done
success "Knowledge base initialised at $KNOWLEDGE_DIR"

# ── 9. nuclei templates ───────────────────────────────────────────────────────
info "Updating nuclei templates..."
nuclei -update-templates -silent 2>/dev/null || true
success "Nuclei templates updated"

# ── 10. Claude Code auth (Claude Max / headless OAuth) ────────────────────────
info "Setting up Claude Code authentication..."
echo ""
echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│          Claude Max — Headless Login Instructions        │${NC}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  Claude Code needs to link to your Claude Max account."
echo -e "  On a headless VPS it can't open a browser, so you do it manually:"
echo ""
echo -e "  ${YELLOW}1.${NC} After this installer finishes, run:  ${CYAN}claude${NC}"
echo -e "  ${YELLOW}2.${NC} Claude Code will print a URL like:   ${CYAN}https://claude.ai/oauth/...${NC}"
echo -e "  ${YELLOW}3.${NC} Open that URL in your ${YELLOW}local browser${NC} (Mac/phone — wherever you're logged in)"
echo -e "  ${YELLOW}4.${NC} Approve the device link"
echo -e "  ${YELLOW}5.${NC} The VPS terminal will confirm auth and drop you into Claude Code"
echo ""
echo -e "  This only needs to happen ${GREEN}once${NC}. The token is saved to ${CYAN}~/.claude/${NC}"
echo -e "  and survives reboots. Re-imaging the VPS requires repeating this step."
echo ""

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Installation complete! ✓          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Start hunting:  ${CYAN}~/launch-bounty.sh${NC}"
echo -e "  Re-attach:      ${CYAN}tmux attach -t bounty${NC}"
echo -e "  Auth Claude:    ${CYAN}claude${NC}  (first run — follow the URL printed)"
echo -e "  Discord env:    ${CYAN}~/.bounty-env${NC}  (chmod 600, gitignored)"
echo -e "  Project dir:    ${CYAN}$WORKDIR${NC}"
echo -e "  Knowledge base: ${CYAN}$KNOWLEDGE_DIR${NC}"
echo ""
