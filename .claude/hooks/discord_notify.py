import sys
import json
import urllib.request
from datetime import datetime, timezone

webhook_url = sys.argv[1]
try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

hook_event  = data.get("hook_event_name", "")
session_id  = data.get("session_id", "unknown")[:8]
cwd         = data.get("cwd", "unknown")
transcript  = data.get("transcript_path", "")
message     = data.get("message", "")
notif_type  = data.get("notification_type", "")
timestamp   = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def send(payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        webhook_url,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "curl/8.5.0"}
    )
    urllib.request.urlopen(req)

def send_chunks(text):
    max_len = 1900
    chunks = []
    while len(text) > max_len:
        split_at = text.rfind('\n', 0, max_len)
        if split_at == -1:
            split_at = max_len
        chunks.append(text[:split_at])
        text = text[split_at:].lstrip('\n')
    if text.strip():
        chunks.append(text)
    total = len(chunks)
    for i, chunk in enumerate(chunks):
        label = f"📋 **Claude Output** (part {i+1}/{total})\n" if total > 1 else "📋 **Claude Output**\n"
        send({"content": label + "```\n" + chunk + "\n```"})

def send_embed(title, desc, color):
    send({"embeds": [{
        "title": title,
        "description": desc,
        "color": color,
        "fields": [
            {"name": "📁 Directory", "value": cwd,               "inline": False},
            {"name": "🔑 Session",   "value": session_id + "...", "inline": True},
        ],
        "footer": {"text": "Claude Code • Bug Bounty"},
        "timestamp": timestamp
    }]})

def get_last_assistant_message():
    if not transcript:
        return ""
    try:
        with open(transcript, "r") as f:
            lines = f.readlines()
        for line in reversed(lines):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("type") == "assistant":
                content = entry.get("message", {}).get("content", "")
                if isinstance(content, list):
                    parts = [b.get("text", "") for b in content
                             if isinstance(b, dict) and b.get("type") == "text"]
                    text = "\n".join(parts).strip()
                elif isinstance(content, str):
                    text = content.strip()
                else:
                    text = ""
                if text:
                    return text
    except Exception as e:
        print(f"Transcript error: {e}", file=sys.stderr)
    return ""

if hook_event == "Stop":
    last = get_last_assistant_message()
    if last:
        send_chunks(last)
    send_embed("✅ Claude finished", "Waiting for your next input.", 2664261)

elif hook_event == "Notification":
    if notif_type == "permission_prompt":
        send_embed("🔐 Permission needed", "Claude is waiting for your approval.", 16761095)
    elif notif_type == "idle_prompt":
        send_embed("💤 Claude is idle", "Waiting for your next instruction.", 16750592)
    else:
        send_embed("🔔 Notification", message, 32767)
