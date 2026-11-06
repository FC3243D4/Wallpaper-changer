#!/usr/bin/env bash
# VicinaeRestarter.sh
# Fully restarts Vicinae so it drops its icon cache and picks up SVGs that
# IconPatcher.sh rewrote in place. Vicinae hot-reloads theme colors by itself,
# but not icon files that kept the same path.
#
# A soft restart (`systemctl restart` / `vicinae server --replace`) was not
# enough here, so this does a hard stop of every process with "vicinae" in
# its name, waits until they are gone, then starts a fresh server.
#
# Run it AFTER IconPatcher.sh has finished, otherwise Vicinae can cache a
# half-written icon again. Does nothing if Vicinae isn't installed or isn't
# running, so it is safe to call unconditionally.
#
# Usage: VicinaeRestarter.sh

command -v vicinae >/dev/null 2>&1 || exit 0
pgrep vicinae >/dev/null 2>&1 || exit 0

# If systemd owns it, stop the unit first so it doesn't respawn mid-kill
usedSystemd=0
if systemctl --user is-active --quiet vicinae.service; then
    usedSystemd=1
    systemctl --user stop vicinae.service
fi

# Kill whatever is left (helper processes survive a plain service restart)
pkill vicinae
for _ in $(seq 1 50); do
    pgrep vicinae >/dev/null 2>&1 || break
    sleep 0.1
done
pkill -9 vicinae 2>/dev/null

if [ "$usedSystemd" -eq 1 ]; then
    systemctl --user start vicinae.service
else
    setsid vicinae server >/dev/null 2>&1 &
    disown
fi

echo "Vicinae restarted"