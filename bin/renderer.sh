#!/bin/sh
# bin/renderer.sh — launch the Quickshell 3D renderer for the Noctalia v5 plugin.
# The service runs this from noctalia.runAsync(), so it must detach: a child
# that stays alive would be killed when the host's short-lived command exits.
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE="${NOCTALIA_LYRICS_CACHE:-$HOME/.cache/noctalia-lyrics}"
mkdir -p "$CACHE"
export NOCTALIA_LYRICS_CACHE="$CACHE"

if ! command -v qs >/dev/null 2>&1; then
    echo "qs (Quickshell) is not installed" >> "$CACHE/renderer.log"
    exit 127
fi

# Reuse a healthy companion. A settings change restarts the Luau service but
# the QML process reads every value from state.json, so restarting it would
# flash the layer (and calibration writes several settings in sequence).
if [ -f "$CACHE/renderer.pid" ]; then
    OLD=$(cat "$CACHE/renderer.pid" 2>/dev/null || true)
    case "$OLD" in
        ''|*[!0-9]*) ;;
        *)
            if [ -r "/proc/$OLD/cmdline" ] && tr '\0' ' ' < "/proc/$OLD/cmdline" | grep -q 'Renderer.qml'; then
                exit 0
            fi
            ;;
    esac
fi

: > "$CACHE/renderer.log"
setsid sh -c 'echo $$ > "$1"; exec qs -p "$2" >> "$3" 2>&1' sh \
    "$CACHE/renderer.pid" "$DIR/ui/Renderer.qml" "$CACHE/renderer.log" \
    < /dev/null > /dev/null 2>&1 &
exit 0
