#!/usr/bin/env bash
# T3MP3ST War Room — self-bootstrapping installer
# One command: brings up the War Room with the OpenCode FREE-model brain, a public
# web link, and automatic scan-report forwarding to Telegram.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/config.env"
# Optional local overrides (secrets) — never committed
if [ -f "$ROOT/config.local.env" ]; then source "$ROOT/config.local.env"; fi

WORK="${T3MP3ST_DIR:-$HOME/t3mp3st}"
PORT="${PORT:-3333}"
say() { printf '\033[1;36m[warroom]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[warroom] %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. dependencies ───────────────────────────────────────────────────────────
command -v git  >/dev/null || die "git is required"
command -v node >/dev/null || die "Node.js (v20+) is required"
command -v tmux >/dev/null || die "tmux is required (apt install tmux / brew install tmux)"

if ! command -v opencode >/dev/null; then
  say "Installing OpenCode CLI (free-tier brain)…"
  npm install -g opencode-ai >/dev/null 2>&1 || die "failed to install opencode-ai (run: npm i -g opencode-ai)"
fi

# ── 2. cloudflared (public tunnel) ────────────────────────────────────────────
CF="${CLOUDFLARED:-$HOME/cloudflared}"
if [ ! -x "$CF" ]; then
  if command -v cloudflared >/dev/null; then CF="$(command -v cloudflared)";
  else
    say "Downloading cloudflared…"
    case "$(uname -m)" in
      x86_64|amd64) A=amd64 ;;
      aarch64|arm64) A=arm64 ;;
      *) A=amd64 ;;
    esac
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${A}" -o "$CF" && chmod +x "$CF" \
      || die "cloudflared download failed — set CLOUDFLARED=/path/to/cloudflared in config.env"
  fi
fi

# ── 3. clone + patch T3MP3ST ──────────────────────────────────────────────────
if [ ! -d "$WORK/.git" ]; then
  say "Cloning $T3MP3ST_REPO…"
  git clone --depth 1 "$T3MP3ST_REPO" "$WORK"
fi
cd "$WORK"
if [ -n "${T3MP3ST_COMMIT:-}" ]; then
  git fetch --depth 1 origin "$T3MP3ST_COMMIT" >/dev/null 2>&1 || true
  git checkout -q "$T3MP3ST_COMMIT" 2>/dev/null || true
fi

say "Applying War Room patches (free-model brain, same-origin UI, tunnel support)…"
if git apply --check "$ROOT/patches/t3mp3st.patch" 2>/dev/null; then
  git apply "$ROOT/patches/t3mp3st.patch"
  say "Patches applied."
elif git apply --check -R "$ROOT/patches/t3mp3st.patch" 2>/dev/null; then
  say "Patches already applied — skipping."
else
  say "Patch did not apply cleanly (upstream changed?) — trying 3-way…"
  git apply --3way "$ROOT/patches/t3mp3st.patch" || say "WARN: patch failed; continuing with unpatched tree."
fi

# ── 4. build ──────────────────────────────────────────────────────────────────
say "Installing dependencies…"
npm install --no-audit --no-fund
say "Building…"
npm run build >/dev/null

# ── 5. configs ────────────────────────────────────────────────────────────────
say "Writing configs…"
mkdir -p "$HOME/.config/opencode"
if [ ! -f "$HOME/.config/opencode/opencode.jsonc" ]; then
  cat > "$HOME/.config/opencode/opencode.jsonc" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "${OPENCODE_FREE_MODEL:-opencode/space-bunny-free}"
}
EOF
fi

mkdir -p "$HOME/.config/t3mp3st-nodejs"
CFG="$HOME/.config/t3mp3st-nodejs/config.json"
if [ -f "$CFG" ]; then
  OPENCODE_FREE_MODEL="${OPENCODE_FREE_MODEL:-opencode/space-bunny-free}" DEFAULT_MODEL="${DEFAULT_MODEL:-opencode::opencode/space-bunny-free}" \
    node -e 'const fs=require("fs"),p=process.env.HOME+"/.config/t3mp3st-nodejs/config.json";const c=JSON.parse(fs.readFileSync(p,"utf8"));c.defaultProvider="local-agent";c.defaultModel=process.env.DEFAULT_MODEL;fs.writeFileSync(p,JSON.stringify(c,null,2));'
else
  cat > "$CFG" <<EOF
{ "apiKeys": {}, "defaultProvider": "local-agent", "defaultModel": "${DEFAULT_MODEL:-opencode::opencode/space-bunny-free}" }
EOF
fi

# ── 6. run (tmux supervisors) ─────────────────────────────────────────────────
say "Starting server + tunnel under tmux…"
tmux kill-session -t t3  >/dev/null 2>&1 || true
tmux kill-session -t tun >/dev/null 2>&1 || true
tmux kill-session -t rep >/dev/null 2>&1 || true

cat > "$WORK/serve-loop.sh" <<EOF
#!/usr/bin/env bash
export T3MP3ST_HOST=0.0.0.0
cd "$WORK"
while true; do npx tsx src/server.ts >> server.log 2>&1; sleep 5; done
EOF
chmod +x "$WORK/serve-loop.sh"
tmux new-session -d -s t3 "bash '$WORK/serve-loop.sh'"

cat > "$WORK/tunnel-loop.sh" <<EOF
#!/usr/bin/env bash
: > "$HOME/.t3_tunnel.log"
while true; do "$CF" tunnel --url http://127.0.0.1:${PORT} --no-autoupdate >> "$HOME/.t3_tunnel.log" 2>&1; sleep 5; done
EOF
chmod +x "$WORK/tunnel-loop.sh"
tmux new-session -d -s tun "bash '$WORK/tunnel-loop.sh'"

# ── 7. report watcher → Telegram ──────────────────────────────────────────────
if [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
  say "Starting Telegram report watcher…"
  tmux new-session -d -s rep "PORT=$PORT TG_BOT_TOKEN='$TG_BOT_TOKEN' TG_CHAT_ID='$TG_CHAT_ID' python3 '$ROOT/scripts/report_watch.py'"
fi

# ── 8. wait for the public URL ────────────────────────────────────────────────
say "Waiting for the public link…"
URL=""
for _ in $(seq 1 40); do
  sleep 3
  URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$HOME/.t3_tunnel.log" 2>/dev/null | tail -1 || true)"
  [ -n "$URL" ] && curl -s -o /dev/null "http://127.0.0.1:${PORT}/api/health" --max-time 5 && break
done

echo
echo "──────────────────────────────────────────────────────────────"
if [ -n "$URL" ]; then
  echo "  ✅ T3MP3ST War Room is LIVE"
  echo "  🌐 $URL/ui/"
  echo "  🔌 API   $URL/api/health"
else
  echo "  ⚠️  Server up on http://127.0.0.1:${PORT}/ui/ (tunnel pending — check ~/.t3_tunnel.log)"
fi
echo "  🧠 Brain: ${DEFAULT_MODEL:-opencode::opencode/space-bunny-free} (OpenCode free tier — no API key)"
echo "──────────────────────────────────────────────────────────────"
echo "  First time only: run 'opencode auth login' so the free models are available."
echo "  Logs:  tmux attach -t t3   /   tmux attach -t tun   /   tmux attach -t rep"
