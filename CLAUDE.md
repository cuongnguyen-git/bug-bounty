# CLAUDE.md

## Goal

Make money from bug bounty. Not submissions. Not learning experiences. **Money.**

This means: **only validated, demonstrable Critical severity findings get submitted.**  
Hight, Medium, Low, and Informational findings are **never** submitted.  
Findings with no working, reproducible PoC are never submitted. When in doubt — do not submit.

---

## Environment

All commands run directly in **Ubuntu WSL** on the local machine. Do not use SSH.  
Tools are installed locally in the Ubuntu WSL environment.  
Ensure `~/go/bin` is in PATH for Go-based recon tools. If it is not, prepend it:

```bash
export PATH=$PATH:~/go/bin
```

## Recon Tools

Recon tools (gau, waybackurls, katana, etc.) are located at `~/go/bin/` in Ubuntu WSL.  
Always verify a tool exists before running it. If a tool is missing, install it automatically:

- **Go tools:** `go install github.com/<tool>@latest`
- **apt tools:** `sudo apt install <tool> -y`
- **pip tools:** `pip3 install <tool> --break-system-packages`
- **GitHub releases:** pull the latest binary, `chmod +x`, move to `~/go/bin/` or `/usr/local/bin/`

Do not stop and ask if a tool is missing — attempt to install it and continue.

---

## Hard Stop Philosophy (Critical Only)

These rules apply to every skill, every session, every finding. No exceptions.

**Never submit / Never pursue:**

- Anything rated Medium or lower (including Informational)
- Anything without a working, reproducible PoC
- Anything where impact requires the words "could", "might", or "potential"
- Anything where the attacker gains nothing actionable or business critical
- Anything where the "exposed" data is already publicly available
- Best practice suggestions (missing headers, cookie flags, TLS versions, etc.)
- Theoretical chains where any step is assumed rather than demonstrated
- Issues that platforms commonly rate as Medium (e.g. most self-XSS, most open redirects without high impact, most rate-limiting bypasses without clear escalation)

If a finding does not clearly qualify as Critical: tell the user directly, explain why, log the pattern, and move on immediately. Do not spend time writing it up.

---

## Hunting Mindset & Persistence

I want you to try your best and hack until you get an outcome.  
**Do not stop until you find me a Critical.**

- Try hard.
- If you feel stuck or want to give up, think from a different angle and try even harder than before.
- Exhaust all reasonable angles on a promising target before moving on.
- When one approach fails, immediately pivot to new hypotheses, new tools, or new attack surfaces.
- Keep going until you either land a valid Critical or have clear evidence the program is extremely dry.

**Persistence is mandatory. Shallow hunting is not allowed.**

---

## Self-Learning System

Maintains a knowledge base at `~/bugbounty/knowledge/` that grows smarter over time.

| File | Purpose |
|---|---|
| `weak-patterns.md` | Findings that failed Critical bar |
| `recon-noise.md` | Finding classes that aren't worth investigating |
| `winning-patterns.md` | Critical findings that paid out |
| `target-notes.md` | Per-target observations that survive context resets |

### Before starting any recon or hypothesis generation

Always read the knowledge base first:

```bash
cat ~/bugbounty/knowledge/weak-patterns.md 2>/dev/null
cat ~/bugbounty/knowledge/recon-noise.md 2>/dev/null
cat ~/bugbounty/knowledge/winning-patterns.md 2>/dev/null
```

Do not repeat investigation of patterns already logged as weak. Skip them and move on.

### Logging a weak pattern

```bash
mkdir -p ~/bugbounty/knowledge
cat >> ~/bugbounty/knowledge/weak-patterns.md << EOF

## $(date +%Y-%m-%d) — Dropped: [short finding description]
**Platform:** [Platform Name]
**Severity:** [Would be Medium/Low or failed Critical]
**Reason:** [why it failed Critical bar — be specific]
**Pattern:** [finding class]
**Target type:** [what kind of app/endpoint]
**Lesson:** [one sentence: what to skip next time]
EOF
```

### Logging a win

```bash
cat >> ~/bugbounty/knowledge/winning-patterns.md << EOF

## $(date +%Y-%m-%d) — Paid: [finding title]
**Platform:** [platform]
**Severity:** [Critical]
**Payout:** [amount if known]
**Pattern:** [finding class]
**What made it work:** [key insight]
**Reuse:** [where else to look for this pattern]
EOF
```

---

## Rules of Engagement

- Authorized, ethical security testing only
- Always stay in scope — do not test assets outside the defined program scope
- No destructive actions — do not modify, delete, or corrupt data on target systems
- All notes, leads, findings, and reports MUST be written to the Ubuntu WSL filesystem (`~/bugbounty/`). Never write to the Windows filesystem (`/mnt/c/`)
- Out-of-scope subdomains: passive recon only — no active testing or payloads

---

## Note Structure

Organize all findings in this hierarchy:

1. **Notes** — everything observed, raw output, tool results
2. **Leads** — interesting things worth investigating further (only Critical potential)
3. **Primitives** — reusable high-value gadgets
4. **Findings** — validated Critical bugs with full end-to-end PoC
5. **Reports** — polished, ready to submit

When documenting a finding, always include the exact full URL, HTTP method, headers, request body, and response snippet.

---

## Autonomy

- If I say I'm stepping away or going to bed, do not ask for input — keep hacking.
- Take thorough notes so you can resume cleanly after context resets.
- Before starting any session, read the knowledge base.
- Combine with the Hunting Mindset above: relentless persistence until a Critical or High is found.

---

## Validation Standard (Critical Only)

- Do not mark something as a Finding unless it clearly qualifies as Critical or High and you have a full end-to-end proof of concept.
- Be extremely strict on impact. Overstating is not allowed.
- **PoC or GTFO.**
- If it's not clearly Critical → $0. Do not submit.
