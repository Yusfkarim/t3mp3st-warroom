# ⚡ T3MP3ST War Room — one-command deploy

Deploy the [T3MP3ST](https://github.com/elder-plinius/T3MP3ST) offensive-security
command center with:

- 🧠 **OpenCode FREE-model brain** (no API key needed — space-bunny / mimo / glm / deepseek)
- 🌐 **A public web link** created automatically (Cloudflare quick tunnel)
- 📲 **Automatic scan reports to your Telegram bot**
- ♻️ **Auto-restart** supervisors (tmux) so it stays up

---

## 🚀 Run it (one command)

```bash
git clone https://github.com/Yusfkarim/t3mp3st-warroom.git
cd t3mp3st-warroom
bash install.sh
```

When it finishes it prints your live link:

```
✅ T3MP3ST War Room is LIVE
🌐 https://xxxx.trycloudflare.com/ui/
🧠 Brain: opencode::opencode/space-bunny-free (no API key)
```

> **First time only:** run `opencode auth login` once so the OpenCode free models
> are available to the brain. After that, everything runs keyless.

Give OpenCode (or anyone) the repo link and say *“run install.sh”* — it does the
rest and hands you a working web link.

---

## 🧠 Switch the brain (free models)

Edit `config.env` and set `DEFAULT_MODEL` to any of:

| Model | Value |
|---|---|
| space-bunny (default) | `opencode::opencode/space-bunny-free` |
| mimo | `opencode::opencode/mimo-v2.6-flash-free` |
| glm | `opencode::opencode/glm-5.3-flash-free` |
| deepseek | `opencode::opencode/deepseek-v4.1-flash-free` |

Then re-run `bash install.sh` (or pick it in the UI → Universal API Config).

---

## 📲 Telegram reports

Every new finding and the final mission report are sent automatically to the bot
configured via `TG_BOT_TOKEN` / `TG_CHAT_ID`. Put them in a **`config.local.env`**
(gitignored, never committed) so secrets stay out of the repo:

```bash
cat > config.local.env <<'EOF'
TG_BOT_TOKEN="123456:ABC..."
TG_CHAT_ID="123456789"
EOF
```

The watcher runs in tmux session `rep`. Test it:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/sendMessage" -d chat_id=<CHAT> -d text="hello"
```

---

## 🛠️ What `install.sh` patches

The script clones T3MP3ST and applies `patches/t3mp3st.patch`:

1. **Free-tier gate fix** — replaces the `{"*":"deny"}` permission that blocks
   OpenCode's free tier (`src/agent/local-agents.ts`).
2. **Free-model default** so keyless local-agent missions work
   (`src/config/index.ts`, `src/server.ts`).
3. **4 free models** added to the model dropdown (`src/config/index.ts`).
4. **Remote UI fix** — the War Room served over the tunnel now talks to the
   same-origin backend instead of falling back to client-side sim
   (`docs/index.html` + no-store headers in `src/server.ts`).

---

## 🔧 Management

```bash
tmux attach -t t3     # server (auto-restarts)
tmux attach -t tun    # tunnel (auto-restarts)
tmux attach -t rep    # telegram report watcher
tmux ls               # list sessions
```

Restart everything: `bash install.sh` again.

Health check:

```bash
curl -s http://127.0.0.1:3333/api/health | python3 -m json.tool
```

---

## ⚠️ Authorized use only

T3MP3ST and this deployment are for **authorized security testing only** — targets
you own or have **written permission** to assess. You are responsible for your use.

---

## 📁 Layout

```
install.sh              # the one-command bootstrap
config.env              # settings (port, model) — no secrets
config.local.env        # YOUR secrets (gitignored, optional)
patches/t3mp3st.patch   # exact patches applied to upstream
scripts/report_watch.py # findings + reports → Telegram
```
