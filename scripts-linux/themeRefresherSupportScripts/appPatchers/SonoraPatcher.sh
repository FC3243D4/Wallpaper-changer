#!/usr/bin/env bash
# SonoraPatcher.sh
# Merges the matugen palette into Sonora's settings.json
# (appearance.theme_overrides). Sonora reads that file only at startup and
# rewrites it from memory on any settings change, so it must only be
# patched while Sonora is closed.
#
# Usage: SonoraPatcher.sh                    patch now, if Sonora is closed
#        SonoraPatcher.sh --pending          exit 0 if settings.json differs from the palette
#        SonoraPatcher.sh --window-state     print normal | special:<name> | hidden
#        SonoraPatcher.sh --launch [args]    patch, then start sonora (used by AppRestarter);
#                                            honours $SONORA_WINDOW_STATE from --window-state

overrides="${XDG_CACHE_HOME:-$HOME/.cache}/sonora-theme/overrides.json"
settings="${XDG_CONFIG_HOME:-$HOME/.config}/sonora/settings.json"

palette_ready() { [ -f "$overrides" ] && jq -e . "$overrides" >/dev/null 2>&1; }

# True when any color in the rendered palette differs from settings.json.
is_pending() {
    palette_ready || return 1
    [ -f "$settings" ] || return 0
    ! jq -e --slurpfile o "$overrides" '
        (.appearance.theme_overrides // {}) as $t
        | $o[0] | to_entries | all(.value == $t[.key])' \
        "$settings" >/dev/null 2>&1
}

apply() {
    if ! palette_ready; then
        echo "sonora: no rendered palette at $overrides, skipping"
        return 0
    fi
    if pgrep -x sonora >/dev/null 2>&1; then
        echo "sonora: running, not patching (it rewrites settings.json from memory)"
        return 0
    fi

    mkdir -p "$(dirname "$settings")"
    [ -f "$settings" ] || echo '{}' > "$settings"

    local tmp
    tmp=$(mktemp "$settings.XXXXXX") || return 1
    if jq --slurpfile o "$overrides" '
        .appearance = ((.appearance // {}) + {
            theme_overrides: ((.appearance.theme_overrides // {}) + $o[0])
        })' "$settings" > "$tmp"; then
        mv "$tmp" "$settings"
        echo "sonora: theme overrides patched"
    else
        rm -f "$tmp"
        echo "sonora: could not parse $settings, left untouched" >&2
        return 1
    fi
}

# Where Sonora's window is right now, so a restart can put it back:
#   normal          on a regular workspace (also: not running, or not Hyprland)
#   special:<name>  parked on a special workspace
#   hidden          running with no window, i.e. closed to the tray
window_state() {
    if [ "$XDG_CURRENT_DESKTOP" != "Hyprland" ] || ! command -v hyprctl >/dev/null 2>&1 \
        || ! pgrep -x sonora >/dev/null 2>&1; then
        echo normal
        return
    fi
    local ws
    ws=$(hyprctl clients -j | jq -r '
        [.[] | select(.class | ascii_downcase == "sonora")][0].workspace.name // empty')
    case "$ws" in
        "")        echo hidden ;;
        special:*) echo "$ws" ;;
        *)         echo normal ;;
    esac
}

sonora_address() {
    hyprctl clients -j | jq -r '
        [.[] | select(.class | ascii_downcase == "sonora")][0].address // empty'
}

# hyprctl dispatch takes a Lua expression on Hyprland 0.55+ (Lua config).
# Invalid dispatchers can still report "ok", so callers verify against
# `hyprctl clients -j` instead of trusting the status.
hl() { hyprctl dispatch "$1" >/dev/null 2>&1; }

window_workspace() {
    hyprctl clients -j | jq -r --arg a "$1" '.[] | select(.address == $a) | .workspace.name'
}

# Starts Sonora straight onto special workspace $1 (silent: no focus change,
# no regular workspace ever sees the window), then optionally closes the
# window ($2 = 1) so Sonora falls back to its tray-only state.
launch_parked() {
    local park="$1" hide="$2" addr="" i

    hl "hl.dsp.exec_cmd(\"sonora\", { workspace = \"$park silent\" })"
    sleep 0.5
    # Dispatch didn't start it: launch plainly, park it below.
    pgrep -x sonora >/dev/null 2>&1 || setsid -f sonora >/dev/null 2>&1

    for i in $(seq 200); do          # up to ~20s for the window to map
        addr=$(sonora_address)
        [ -n "$addr" ] && break
        sleep 0.1
    done
    [ -n "$addr" ] || { echo "sonora: window never appeared" >&2; return 1; }

    # Rule not honoured (or launched plainly): move it silently ourselves.
    if [ "$(window_workspace "$addr")" != "$park" ]; then
        hl "hl.dsp.window.move({ workspace = \"$park\", follow = false, window = \"address:$addr\" })"
        sleep 0.2
        [ "$(window_workspace "$addr")" = "$park" ] \
            || echo "sonora: could not park the window on $park" >&2
    fi

    if [ "$hide" = "1" ]; then
        sleep 0.3
        hl "hl.dsp.window.close({ window = \"address:$addr\" })"
    fi
}

case "$1" in
    "")            apply ;;
    --pending)     is_pending ;;
    --window-state) window_state ;;
    --launch)
        shift
        apply
        state="${SONORA_WINDOW_STATE:-normal}"
        case "$state" in
            hidden)    launch_parked "special:sonora-restart" 1 ;;
            special:*) launch_parked "$state" 0 ;;
            *)         exec sonora "$@" ;;
        esac
        ;;
    *)             echo "Usage: $0 [--pending|--window-state|--launch [args]]" >&2; exit 1 ;;
esac