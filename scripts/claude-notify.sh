#!/bin/bash
# Claude Code hook -> Liftoff notification bridge.
# Title = project folder, message = Claude's actual message.
# Sends to the app's localhost listener; silently no-ops otherwise.

echo "$(date '+%H:%M:%S') invoked LIFTOFF=${LIFTOFF:-unset} TERM_PROGRAM=${TERM_PROGRAM:-unset}" >> /tmp/liftoff-notify.log

# Only fire for sessions running inside Liftoff terminals.
# LIFTOFF is only set in shells the app spawned, so no extra running-check needed.
[ -n "$LIFTOFF" ] || exit 0

url=$(/usr/bin/python3 -c '
import sys, json, os, urllib.parse

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cwd = d.get("cwd") or ""
title = os.path.basename(cwd) if cwd else "Claude Code"
event = d.get("hook_event_name", "")
msg = ""

if event == "Notification":
    msg = d.get("message") or ""
else:
    # Stop: pull Claude last assistant text from the session transcript.
    path = d.get("transcript_path") or ""
    try:
        f = open(path)
    except Exception:
        f = None
    if f:
        with f:
            for line in f:
                try:
                    e = json.loads(line)
                    if e.get("type") != "assistant":
                        continue
                    parts = e.get("message", {}).get("content", [])
                    if not isinstance(parts, list):
                        continue
                    text = " ".join(
                        p.get("text", "") for p in parts
                        if isinstance(p, dict) and p.get("type") == "text"
                    ).strip()
                    if text:
                        msg = text
                except Exception:
                    continue

msg = " ".join(msg.split())

def summarize(text):
    # Optional: condense long messages via an Ollama-compatible chat endpoint.
    # Configure with LIFTOFF_GATE_URL / LIFTOFF_GATE_MODEL / LIFTOFF_GATE_TOKEN;
    # without LIFTOFF_GATE_URL this is a no-op and the raw message is truncated.
    gate = os.environ.get("LIFTOFF_GATE_URL", "")
    if not gate:
        return None
    import urllib.request
    body = {
        "stream": False,
        "messages": [
            {"role": "system", "content": "Summarize the assistant message into ONE short plain-text sentence (max 15 words) for a desktop notification. No markdown, no quotes, no preamble."},
            {"role": "user", "content": text[:4000]},
        ],
    }
    model = os.environ.get("LIFTOFF_GATE_MODEL", "")
    if model:
        body["model"] = model
    req = urllib.request.Request(
        gate.rstrip("/") + "/api/chat",
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + os.environ.get("LIFTOFF_GATE_TOKEN", ""),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            out = json.load(r).get("message", {}).get("content", "").strip()
            if out:
                return " ".join(out.split())
    except Exception:
        pass
    return None

if len(msg) > 120:
    msg = summarize(msg) or msg
if len(msg) > 180:
    msg = msg[:177] + "..."
if not msg:
    msg = "Claude finished working" if event != "Notification" else "Claude needs your attention"

q = urllib.parse.urlencode({"title": title, "message": msg}, quote_via=urllib.parse.quote)
print("http://127.0.0.1:48623/notify?" + q)
' 2>>/tmp/liftoff-notify.log)

echo "$(date '+%H:%M:%S') url=$url" >> /tmp/liftoff-notify.log
[ -n "$url" ] && curl -s -m 2 "$url" >/dev/null 2>&1
exit 0
