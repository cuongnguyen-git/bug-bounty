---
name: new-target
description: Run a full first-time recon on a new bug bounty target program. Use when starting on a brand new program for the first time. Reads scope from ~/bugbounty/[target]/scope.md in Kali WSL.
allowed-tools: Bash
---

# New Target Recon

Program: $ARGUMENTS

All commands run directly in Kali WSL. No SSH.
Ensure tools are available at `~/go/bin/` — if missing, install automatically before proceeding.
Save all output to `~/bugbounty/$ARGUMENTS/recon/` in Kali WSL. Never write to /mnt/c/.

**Do not attempt to exploit anything. Recon and mapping only.**

---

## Step 0 — Ensure PATH

```bash
export PATH=$PATH:~/go/bin
```

---

## Pre-flight

Read the knowledge base before doing anything else:

```bash
cat ~/bugbounty/knowledge/weak-patterns.md 2>/dev/null || echo "No weak patterns yet"
cat ~/bugbounty/knowledge/recon-noise.md 2>/dev/null || echo "No recon noise yet"
cat ~/bugbounty/knowledge/winning-patterns.md 2>/dev/null || echo "No winning patterns yet"
```

Verify scope file exists and tools are available:

```bash
cat ~/bugbounty/$ARGUMENTS/scope.md
```

```bash
which ~/go/bin/subfinder ~/go/bin/httpx ~/go/bin/gau ~/go/bin/waybackurls ~/go/bin/katana ~/go/bin/nuclei 2>&1
```

If `scope.md` is missing or empty — stop and tell the user to create it before continuing.

If any tool is missing — attempt to install it automatically before proceeding:

```bash
# subfinder
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest

# httpx
go install github.com/projectdiscovery/httpx/cmd/httpx@latest

# gau
go install github.com/lc/gau/v2/cmd/gau@latest

# waybackurls
go install github.com/tomnomnom/waybackurls@latest

# katana
go install github.com/projectdiscovery/katana/cmd/katana@latest

# nuclei
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
```

Create output directory:

```bash
mkdir -p ~/bugbounty/$ARGUMENTS/recon
```

---

## Scope Parsing

Read `scope.md` and split into two lists:

- **Root domains** — lines with no wildcard (e.g. `example.com`)
- **Wildcard domains** — lines starting with `*.` (e.g. `*.example.com`) — strip the `*.` to get the root for enumeration

Combine both into a single deduplicated root domain list and save it:

```bash
grep -v '^\s*$' ~/bugbounty/$ARGUMENTS/scope.md | sed 's/^\*\.//' | sort -u > ~/bugbounty/$ARGUMENTS/recon/scope-roots.txt && cat ~/bugbounty/$ARGUMENTS/recon/scope-roots.txt
```

All recon phases run against every root in `scope-roots.txt`.

---

## Phase 1 — Subdomain Enumeration (15 min)

Run subfinder, gau, and waybackurls against every root domain in scope:

```bash
while read domain; do
  ~/go/bin/subfinder -d $domain -silent
  echo $domain | ~/go/bin/gau --subs 2>/dev/null | grep -oP 'https?://\K[^/]+'
  echo $domain | ~/go/bin/waybackurls 2>/dev/null | grep -oP 'https?://\K[^/]+'
done < ~/bugbounty/$ARGUMENTS/recon/scope-roots.txt | sort -u > ~/bugbounty/$ARGUMENTS/recon/01-subdomains.txt && wc -l ~/bugbounty/$ARGUMENTS/recon/01-subdomains.txt
```

---

## Phase 2 — Live Host Discovery (10 min)

```bash
cat ~/bugbounty/$ARGUMENTS/recon/01-subdomains.txt | ~/go/bin/httpx -silent -status-code -title -tech-detect -o ~/bugbounty/$ARGUMENTS/recon/02-live-hosts.txt && wc -l ~/bugbounty/$ARGUMENTS/recon/02-live-hosts.txt
```

Flag any hosts returning 200 with interesting titles. Note anything that looks like admin panels, APIs, or internal tooling.

---

## Phase 3 — Tech Stack Fingerprinting (10 min)

Extract technology signals from httpx output:

```bash
grep -oP '\[[^\]]+\]' ~/bugbounty/$ARGUMENTS/recon/02-live-hosts.txt | sort | uniq -c | sort -rn | head -40
```

Analyze for:
- Server, framework, CDN, WAF indicators
- Version numbers in headers or response bodies
- Frontend framework signals from JS bundle names

Save all identified technologies and versions to `03-tech-stack.md`. Every version number feeds Phase 6.

---

## Phase 4 — Endpoint Mapping (15 min)

Run katana against all live hosts, and gau/waybackurls against all scope roots:

```bash
awk '{print $1}' ~/bugbounty/$ARGUMENTS/recon/02-live-hosts.txt | ~/go/bin/katana -silent -d 3 -o ~/bugbounty/$ARGUMENTS/recon/katana.txt 2>/dev/null
```

```bash
while read domain; do
  echo $domain | ~/go/bin/gau --blacklist png,jpg,gif,svg,css,woff,woff2 2>/dev/null
  echo $domain | ~/go/bin/waybackurls 2>/dev/null
done < ~/bugbounty/$ARGUMENTS/recon/scope-roots.txt | sort -u > ~/bugbounty/$ARGUMENTS/recon/07-historical-urls.txt
```

Combine and filter for interesting patterns:

```bash
cat ~/bugbounty/$ARGUMENTS/recon/katana.txt ~/bugbounty/$ARGUMENTS/recon/07-historical-urls.txt | sort -u | grep -iE '(api|admin|auth|token|key|secret|internal|debug|v1|v2|graphql|swagger|config|reset|password|upload|export|download|backup|\.json|\.xml|\.env)' > ~/bugbounty/$ARGUMENTS/recon/04-endpoints.txt && wc -l ~/bugbounty/$ARGUMENTS/recon/04-endpoints.txt
```

---

## Phase 5 — JS Recon (10 min)

Extract first-party JS file URLs:

```bash
cat ~/bugbounty/$ARGUMENTS/recon/07-historical-urls.txt ~/bugbounty/$ARGUMENTS/recon/katana.txt | grep '\.js' | grep -v '\.json' | grep -v -iE '(jquery|bootstrap|cdn\.|cloudflare|googleapis|facebook|twitter|analytics)' | sort -u > ~/bugbounty/$ARGUMENTS/recon/js-files.txt && wc -l ~/bugbounty/$ARGUMENTS/recon/js-files.txt
```

Run LinkFinder and SecretFinder on first-party JS:

```bash
head -30 ~/bugbounty/$ARGUMENTS/recon/js-files.txt | while read url; do
  echo "=== $url ==="
  python3 ~/tools/LinkFinder/linkfinder.py -i $url -o cli 2>/dev/null
done | sort -u > ~/bugbounty/$ARGUMENTS/recon/js-endpoints.txt
```

```bash
head -30 ~/bugbounty/$ARGUMENTS/recon/js-files.txt | while read url; do
  echo "=== $url ==="
  python3 ~/tools/SecretFinder/SecretFinder.py -i $url -o cli 2>/dev/null
done > ~/bugbounty/$ARGUMENTS/recon/05-js-secrets.md
```

If LinkFinder or SecretFinder are not at `~/tools/`, install them:

```bash
# LinkFinder
git clone https://github.com/GerbenJavado/LinkFinder.git ~/tools/LinkFinder
pip3 install -r ~/tools/LinkFinder/requirements.txt --break-system-packages

# SecretFinder
git clone https://github.com/m4ll0k/SecretFinder.git ~/tools/SecretFinder
pip3 install -r ~/tools/SecretFinder/requirements.txt --break-system-packages
```

---

## Phase 6 — CVE Lookup (5 min)

Run targeted nuclei CVE templates against live hosts — critical and high only:

```bash
awk '{print $1}' ~/bugbounty/$ARGUMENTS/recon/02-live-hosts.txt | ~/go/bin/nuclei -t ~/nuclei-templates/cves/ -severity critical,high -silent -o ~/bugbounty/$ARGUMENTS/recon/08-cves.md 2>/dev/null
```

If nuclei-templates are not present, update them first:

```bash
~/go/bin/nuclei -update-templates
```

Do not run full nuclei scans. CVE templates only.

---

## Phase 7 — Summary (5 min)

Write `~/bugbounty/$ARGUMENTS/recon/00-summary.md`:

```
# Recon Summary — $ARGUMENTS
Date: [date]

## Scope
[list all in-scope roots from scope.md]

## Numbers
- Root domains in scope: [count]
- Subdomains discovered: [count]
- Live hosts: [count]
- Endpoints mapped: [count]
- JS files analyzed: [count]

## Tech Stack
[identified technologies and versions]

## Top Endpoints for Manual Testing
[5-10 most interesting, with reason for each]

## Secrets / Keys Found
[any hardcoded credentials, tokens, API keys — with source file]

## CVEs
[any relevant CVEs for identified versions]

## Suggested Starting Points
[specific hypotheses — IDOR surfaces, auth endpoints, etc.]

## Notes
[anything unusual, out of scope items encountered, rate limiting, etc.]
```

---

## Phase 8 — JS Attack Surface Analysis

Read and execute the skill at `/home/cuong/claude-cuong/skills/js-attack-surface.md`.

Pick the top 3 JS-heavy targets from `02-live-hosts.txt` — prioritize hosts with `[React]`, `[Vue]`, `[Next.js]`, or `[Angular]` in the httpx tech-detect output, then any auth or API endpoints.

Run the js-attack-surface skill on each selected target URL one at a time, passing the target URL as the argument.

---

## Phase 9 — Hypothesis Generation

Read and execute the skill at `/home/cuong/claude-cuong/skills/hypothesis-agent.md`.

Pass `~/bugbounty/$ARGUMENTS` as the argument.

This runs last so the hypothesis agent has the full recon picture: subdomains, live hosts, tech stack, endpoints, JS findings, CVEs, and the summary.

---

## Hard Rules

- Do not brute force anything
- Do not send more than normal recon-level traffic
- Do not run nuclei full scans — targeted CVE templates, critical/high only
- If you find what looks like a confirmed vulnerability, note it in the summary and stop — do not investigate further. That belongs in a separate hacking workflow.
- Only test hosts that match the original scope in scope.md — do not follow links off-scope
- Never write files to /mnt/c/ — all output stays within ~/bugbounty/ in Kali WSL
- Use ~/go/bin/ paths for all Go tools
