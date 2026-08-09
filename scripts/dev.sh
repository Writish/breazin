#!/bin/bash
# scripts/dev.sh — build the debug bundle, launch it, and stream its OSLog.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

stream=true
for arg in "$@"; do
    case "$arg" in
        --no-stream) stream=false ;;
    esac
done

"$ROOT/scripts/bundle.sh" debug --fast

case "${BREAZIN_ENVIRONMENT:-development}" in
    development) subsystem="com.writish.breazin.dev" ;;
    staging) subsystem="com.writish.breazin.beta" ;;
    production) subsystem="com.writish.breazin" ;;
    *) echo "Unknown BREAZIN_ENVIRONMENT" >&2; exit 1 ;;
esac

if ! $stream; then
    open "$ROOT/.build/Breazin.app"
    exit 0
fi

echo "Streaming OSLog (subsystem=$subsystem). Ctrl-C to quit app and stop." >&2
echo >&2

cleanup() {
    pid=$(pgrep -f "Breazin.app/Contents/MacOS/Breazin" | head -1 || true)
    if [ -n "$pid" ]; then
        osascript -e 'quit app "Breazin"' 2>/dev/null || kill "$pid" 2>/dev/null || true
    fi
}
trap cleanup INT TERM EXIT

( sleep 0.5 && open "$ROOT/.build/Breazin.app" ) &
log stream \
    --predicate "subsystem == '$subsystem'" \
    --level info \
    --style compact
