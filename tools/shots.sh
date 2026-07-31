#!/usr/bin/env bash
# Capture frames from the running spike, at pinned cycle-times.
#
# The point is reproducibility: `?t=` freezes the world clock, so the same
# invocation always produces the same pixels and two runs can be compared.
#
#   tools/shots.sh                    # default sweep, one frame per scene
#   tools/shots.sh 12 29 148 250      # specific cycle-times, in seconds
#   OUT=/tmp/x HUD=1 tools/shots.sh   # keep the debug overlay
#
# Needs a static server on $PORT rooted at the repo (see app/README.md) and
# Google Chrome. No npm install, no Playwright.

set -euo pipefail
export LC_ALL=C   # keep printf decimal points as dots, not locale commas

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${PORT:-8123}"
OUT="${OUT:-$(cd "$(dirname "$0")/.." && pwd)/.shots}"
SIZE="${SIZE:-1280,720}"
HUD="${HUD:-0}"

TIMES=("$@")
if [ ${#TIMES[@]} -eq 0 ]; then
  # one representative frame from each scene of case 001
  TIMES=(29 62 148 172 236 268 322 352 420 470 505)
fi

if [ ! -x "$CHROME" ]; then
  echo "Chrome not found at: $CHROME" >&2
  echo "Set CHROME=/path/to/chrome" >&2
  exit 1
fi

if ! curl -sf -o /dev/null "http://localhost:$PORT/demo-world/chunk.json"; then
  echo "No server on :$PORT — run  python3 -m http.server $PORT  from the repo root" >&2
  exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT"/*.png

for t in "${TIMES[@]}"; do
  name=$(printf "t%06.1f" "$t")
  "$CHROME" \
    --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size="$SIZE" \
    --virtual-time-budget=4000 \
    --screenshot="$OUT/$name.png" \
    "http://localhost:$PORT/app/index.html?t=$t&hud=$HUD" \
    >/dev/null 2>&1
  echo "  $name.png"
done

echo "-> $OUT"
