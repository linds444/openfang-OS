#!/bin/bash
# OpenFang OS — Desktop startup hook (runs after XFCE login)

# Wait for desktop to settle
sleep 3

# Check if OpenFang API is available — if not, show a notification
if ! curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
    if command -v notify-send >/dev/null 2>&1; then
        notify-send \
            --icon=dialog-warning \
            --urgency=normal \
            --app-name="OpenFang OS" \
            "AI Runtime Offline" \
            "The OpenFang agent runtime is not running.\nOpen a terminal and run: sudo systemctl start openfang"
    fi
fi

# Set desktop wallpaper if it exists
if [ -f /usr/share/openfang/wallpaper.png ]; then
    xfconf-query -c xfce4-desktop \
        -p /backdrop/screen0/monitorVirtual-1/workspace0/last-image \
        -s /usr/share/openfang/wallpaper.png 2>/dev/null || true
fi

# Set trusted on Desktop .desktop files
for f in ~/Desktop/*.desktop; do
    [ -f "$f" ] && gio set "$f" metadata::trusted true 2>/dev/null || true
done

# Start nm-applet if not already running
pgrep -x nm-applet >/dev/null || nm-applet &

# Start notification daemon
pgrep -x xfce4-notifyd >/dev/null || xfce4-notifyd &
