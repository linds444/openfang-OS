#!/bin/bash
# OpenFang OS — Desktop startup hook (runs after XFCE login)

# Wait for desktop to settle
sleep 3

# ── Create standard XDG user directories ─────────────────────────────────────
xdg-user-dirs-update 2>/dev/null || true
# Ensure Desktop folder exists and is populated
mkdir -p ~/Desktop ~/Documents ~/Downloads ~/Music ~/Pictures ~/Videos ~/Templates ~/Public

# ── Trust desktop .desktop files so they launch on double-click ───────────────
for f in ~/Desktop/*.desktop; do
    [ -f "$f" ] || continue
    chmod +x "$f"
    gio set "$f" metadata::trusted true 2>/dev/null || true
done

# ── Set desktop wallpaper ─────────────────────────────────────────────────────
if [ -f /usr/share/openfang/wallpaper.png ]; then
    # Apply to all known monitor/workspace combinations
    for monitor in Virtual-1 HDMI-1 DP-1 eDP-1 VGA-1; do
        xfconf-query -c xfce4-desktop \
            -p "/backdrop/screen0/monitor${monitor}/workspace0/last-image" \
            -s /usr/share/openfang/wallpaper.png 2>/dev/null || true
        xfconf-query -c xfce4-desktop \
            -p "/backdrop/screen0/monitor${monitor}/workspace0/image-style" \
            -s 5 2>/dev/null || true
    done
fi

# ── Start system tray services ────────────────────────────────────────────────
pgrep -x nm-applet     >/dev/null || nm-applet &
pgrep -x xfce4-notifyd >/dev/null || xfce4-notifyd &
pgrep -x pulseaudio    >/dev/null || pulseaudio --start 2>/dev/null || true

# ── Set default terminal application ─────────────────────────────────────────
xfconf-query -c xfce4-keyboard-shortcuts \
    -p "/commands/custom/<Primary><Alt>t" \
    --create -t string -s "xfce4-terminal" 2>/dev/null || true

# ── Set composite (transparency) and display compositor ──────────────────────
xfconf-query -c xfwm4 -p /general/use_compositing \
    --create -t bool -s true 2>/dev/null || true

# ── Check if OpenFang API is available ───────────────────────────────────────
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
