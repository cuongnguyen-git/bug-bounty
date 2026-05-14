# bug-bounty-setup

One-command VPS bootstrap for Claude Code bug bounty hunting.

## Setup

```bash
git clone https://github.com/YOUR_USERNAME/bug-bounty-setup.git
cd bug-bounty-setup
chmod +x install.sh
./install.sh
```

Prompts for your Discord webhook URL only. No API key needed — uses Claude Max via OAuth.

## First run auth

After install:

```bash
~/launch-bounty.sh
```

Claude Code will print a URL in the claude window. Open it in your local browser (where you're signed into Claude Max), approve, done. Token is saved permanently — never needed again unless you wipe the VPS.

## Structure after install

```
/home/codeine/
├── .bounty-env              # Discord webhook (chmod 600, gitignored)
├── launch-bounty.sh         # start/re-attach tmux
└── bug-bounty/
    ├── CLAUDE.md            # hunting instructions
    ├── knowledge/           # self-learning knowledge base
    │   ├── weak-patterns.md
    │   ├── recon-noise.md
    │   ├── winning-patterns.md
    │   └── target-notes.md
    └── .claude/
        ├── settings.json    # discord hooks (generated, gitignored)
        ├── hooks/
        │   ├── discord-notify.sh
        │   └── discord_notify.py
        └── skills/
```

## tmux windows

| Window | Purpose |
|---|---|
| `0 claude` | Claude Code |
| `1 workspace` | your shell |
| `2 monitor` | htop |

Re-attach after disconnect: `tmux attach -t bounty`

## Adding skills

Drop files into `.claude/skills/` — copied to the VPS on install.

## Re-running install

Safe to re-run. Existing secrets and knowledge base are preserved.
