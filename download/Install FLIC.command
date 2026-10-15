#!/bin/bash
# =============================================================================
#  Install FLIC — double-click this file.
#
#  Sets up everything FLIC needs on an Apple Silicon Mac (macOS 14 or newer):
#    Homebrew, ffmpeg, Node, Python, yt-dlp, Ollama + its AI model, the Whisper
#    speech model, FLIC itself in ~/FLIC, the folder watcher (starts at login) and
#    "Start FLIC" / "Stop FLIC" on your Desktop.
#
#  Needs: your FLIC license key (from your Whop purchase), ~20 GB free, internet.
#  Takes 15–40 minutes, mostly downloads. Safe to run again: it only fills in what
#  is missing and keeps your input/, output/ and campaigns/.
# =============================================================================
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SITE="${FLIC_SITE:-https://flicclips.pages.dev}"
FLIC_DIR="$HOME/FLIC"
VENV="$FLIC_DIR/.venv"
OLLAMA_MODEL="llama3.1:8b"
WHISPER_REPO="mlx-community/whisper-large-v3-turbo"
LOG="$HOME/Library/Logs/flic-install.log"
mkdir -p "$(dirname "$LOG")"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
say()  { printf '  %s\n' "$*"; }
die()  { printf '\n\033[1;31m  %s\033[0m\n\n' "$*"; printf '  Log: %s\n\n' "$LOG"; read -r -p "  Press Return to close. "; exit 1; }
step() { bold "$1"; echo "== $1" >> "$LOG"; }
run()  { "$@" >> "$LOG" 2>&1; }

clear
printf '\n\033[1m  FLIC installer\033[0m\n  Turn long videos into ready-to-post clips, on your own Mac.\n\n'

# ── 0. This Mac ───────────────────────────────────────────────────────────────
[ "$(uname -s)" = "Darwin" ] || die "FLIC runs on macOS only."
[ "$(uname -m)" = "arm64" ] || die "FLIC needs an Apple Silicon Mac (M1 or newer). This Mac has an Intel chip."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] 2>/dev/null || die "FLIC needs macOS 14 (Sonoma) or newer. This Mac runs $(sw_vers -productVersion)."
FREE_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
[ "${FREE_GB:-0}" -ge 20 ] || die "FLIC needs about 20 GB free; this Mac has ${FREE_GB} GB. Free some space and run this again."

# ── 1. License ────────────────────────────────────────────────────────────────
step "1/8  License"
KEY=""
if [ -f "$FLIC_DIR/.license" ]; then
  KEY="$(tr -d '[:space:]' < "$FLIC_DIR/.license")"
  say "found a saved license key"
fi
if [ -z "$KEY" ]; then
  say "Your license key is on your Whop purchase page (Whop → your FLIC order → License key)."
  read -r -p "  Paste your license key: " KEY
  KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
fi
[ -n "$KEY" ] || die "No license key entered."
RESP="$(curl -sS -m 20 -X POST "$SITE/api/license" -H 'Content-Type: application/json' \
        -d "{\"key\":\"$KEY\",\"reason\":\"install\"}" 2>>"$LOG")" || die "Could not reach $SITE. Check your internet and run this again."
OK="$(printf '%s' "$RESP" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print("yes" if d.get("ok") else "no")' 2>/dev/null)"
if [ "$OK" != "yes" ]; then
  MSG="$(printf '%s' "$RESP" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("message","License key not accepted."))' 2>/dev/null)"
  die "${MSG:-License key not accepted.}"
fi
DL="$(printf '%s' "$RESP" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("download",""))')"
[ -n "$DL" ] || die "License accepted but no download link came back. Try again in a minute."
say "license OK"

# ── 2. Xcode command line tools + Homebrew ────────────────────────────────────
step "2/8  Homebrew (the Mac package manager)"
if ! xcode-select -p >/dev/null 2>&1; then
  say "macOS will show a window asking to install the Command Line Tools. Click Install, then wait here."
  xcode-select --install >/dev/null 2>&1 || true
  until xcode-select -p >/dev/null 2>&1; do sleep 10; done
fi
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew. It will ask for your Mac password (nothing shows while you type), then press Return."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew did not install."
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
say "Homebrew ready"

# ── 3. Tools ──────────────────────────────────────────────────────────────────
step "3/8  ffmpeg, Node, Python, yt-dlp, Ollama"
for pkg in ffmpeg node python@3.12 yt-dlp ollama; do
  if brew list --formula "$pkg" >/dev/null 2>&1; then say "$pkg: already installed"
  else say "installing $pkg ..."; run brew install "$pkg" || die "Could not install $pkg."; fi
done
PY="$(brew --prefix python@3.12)/bin/python3.12"
[ -x "$PY" ] || die "Python 3.12 not found after install."

# ── 4. FLIC itself ────────────────────────────────────────────────────────────
step "4/8  FLIC program files -> $FLIC_DIR"
TMP="$(mktemp -d)"
curl -sS -L -m 300 -o "$TMP/flic.zip" "$DL" 2>>"$LOG" || die "Download failed."
mkdir -p "$FLIC_DIR"
if [ -d "$FLIC_DIR/engine" ]; then
  say "updating an existing FLIC (your input/, output/, campaigns/ and transcripts are kept)"
  mkdir -p "$FLIC_DIR/campaigns/_prev"
  cp "$FLIC_DIR"/campaigns/*.yaml "$FLIC_DIR/campaigns/_prev/" 2>/dev/null || true
fi
run ditto -x -k "$TMP/flic.zip" "$TMP/unz" || die "Could not unpack FLIC."
SRC="$(find "$TMP/unz" -maxdepth 2 -name engine -type d | head -1)"; SRC="$(dirname "$SRC")"
run ditto "$SRC" "$FLIC_DIR" || die "Could not copy FLIC into place."
rm -rf "$TMP"
printf '%s\n' "$KEY" > "$FLIC_DIR/.license"; chmod 600 "$FLIC_DIR/.license"
mkdir -p "$FLIC_DIR/input" "$FLIC_DIR/output" "$FLIC_DIR/logs" "$FLIC_DIR/transcripts"
say "files in place"

# ── 5. Python packages (in FLIC's own folder, nothing else on the Mac is touched) ─
step "5/8  Python packages (speech, face tracking, audio)"
[ -x "$VENV/bin/python3" ] || run "$PY" -m venv "$VENV" || die "Could not create the Python environment."
run "$VENV/bin/pip" install --upgrade pip
run "$VENV/bin/pip" install -r "$FLIC_DIR/engine/installer/requirements.txt" || die "Python packages failed to install. See the log."
say "done"

# ── 6. AI models ──────────────────────────────────────────────────────────────
step "6/8  AI models (about 7 GB, one time)"
run brew services start ollama || true
for _ in $(seq 1 30); do curl -s -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break; sleep 2; done
curl -s -m 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 || die "Ollama (the local AI) did not start. Open Terminal, run: brew services restart ollama, then run this installer again."
if ollama list 2>/dev/null | grep -q "^${OLLAMA_MODEL}"; then say "$OLLAMA_MODEL: already downloaded"
else say "downloading $OLLAMA_MODEL (about 5 GB) ..."; ollama pull "$OLLAMA_MODEL" 2>&1 | tr '\r' '\n' | grep -E "^(pulling|success|verifying)" | tail -1; fi
say "downloading the speech model (about 1.5 GB) ..."
run "$VENV/bin/python3" -c "from huggingface_hub import snapshot_download; snapshot_download('$WHISPER_REPO')" || die "Speech model download failed. See the log."
say "models ready"

# ── 7. Watcher + Desktop buttons ──────────────────────────────────────────────
step "7/8  Folder watcher (starts at login) + Desktop buttons"
run bash "$FLIC_DIR/engine/scripts/install_watcher.sh" || die "Could not register the watcher."
for f in "Start FLIC.command" "Stop FLIC.command"; do
  cp "$FLIC_DIR/engine/installer/$f" "$HOME/Desktop/$f" && chmod +x "$HOME/Desktop/$f"
done
say "watcher running; Start FLIC / Stop FLIC are on your Desktop"

# ── 8. Check ──────────────────────────────────────────────────────────────────
step "8/8  Self-check"
PROBLEMS=0
for t in ffmpeg node yt-dlp ollama; do command -v "$t" >/dev/null 2>&1 || { say "missing: $t"; PROBLEMS=1; }; done
"$VENV/bin/python3" -c "import mlx_whisper, cv2, librosa, yaml" 2>>"$LOG" || { say "a Python package failed to load"; PROBLEMS=1; }
pgrep -f "engine/scripts/watch.py" >/dev/null || { say "watcher is not running"; PROBLEMS=1; }
[ "$PROBLEMS" -eq 0 ] || die "Something is missing (see above). Run this installer again; if it still fails, send the log to support."

bold "  FLIC is installed."
say "How to use it: the guide is opening now (also at ~/FLIC/input/README.html)."
say "Short version: drop a video + brief.txt into ~/FLIC/input and FLIC does the rest."
echo
open "$FLIC_DIR/input/README.html"
read -r -p "  Press Return to close. "
