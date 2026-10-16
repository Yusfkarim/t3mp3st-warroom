#!/usr/bin/env python3
"""Watch T3MP3ST and forward mission findings + final reports to Telegram."""
import json
import os
import time
import urllib.parse
import urllib.request

PORT = os.environ.get("PORT", "3333")
TOKEN = os.environ.get("TG_BOT_TOKEN", "").strip()
CHAT = os.environ.get("TG_CHAT_ID", "").strip()
BASE = f"http://127.0.0.1:{PORT}"


def api(path):
    try:
        with urllib.request.urlopen(BASE + path, timeout=10) as r:
            return json.load(r)
    except Exception:
        return None


def send(text):
    if not TOKEN or not CHAT:
        return
    data = urllib.parse.urlencode({"chat_id": CHAT, "text": text}).encode()
    try:
        urllib.request.urlopen(
            f"https://api.telegram.org/bot{TOKEN}/sendMessage", data=data, timeout=20
        )
    except Exception as e:  # noqa: BLE001
        print("telegram send failed:", e, flush=True)


def main():
    if not TOKEN or not CHAT:
        print("No TG_BOT_TOKEN / TG_CHAT_ID — watcher idle.", flush=True)
        return
    seen = set()
    last_active = False
    last_name = ""
    print("report watcher online", flush=True)
    while True:
        d = api("/api/mission/status")
        if d:
            active = bool(d.get("active"))
            name = d.get("name") or last_name or "mission"
            for f in d.get("findings", []) or []:
                fid = f.get("id") or f"{f.get('severity')}:{f.get('title', f.get('type'))}"
                if fid not in seen:
                    seen.add(fid)
                    send(
                        f"🔎 [{f.get('severity', '?')}] "
                        f"{f.get('title') or f.get('type') or 'finding'}\n"
                        f"target: {f.get('target', '-')}\nmission: {name}"
                    )
            if active and not last_active:
                send(f"🎯 Mission started: {name}")
            if last_active and not active:
                rep = api("/api/mission/report") or {}
                report = rep.get("report", "")
                if report:
                    send(f"📄 Report — {name}\n\n{report[:3500]}")
                else:
                    send(f"🛑 Mission finished: {name} (no report body)")
            last_active = active
            if active:
                last_name = name
        time.sleep(10)


if __name__ == "__main__":
    main()
