#!/bin/bash
# Theme the Plasma Login Manager (Fedora 44's login screen, the SDDM successor)
# to match the NordicForest desktop: wallpaper, colours, MonaspiceNe font.
#
#   sudo ./install-sddm.sh          install (safe to run again)
#   sudo ./install-sddm.sh --undo   remove it and restore the backup
#
# Takes effect the next time the login screen starts (log out or reboot).
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
FONT_DIR=/usr/local/share/fonts/MonaspiceNe
WALL_DIR=/usr/local/share/wallpapers/nordicforest
CONF=/etc/plasmalogin.conf.d/10-nordicforest.conf
GREETER_HOME=/var/lib/plasmalogin
GREETER_GLOBALS=$GREETER_HOME/.config/kdeglobals
BACKUP=/var/backups/rice-nordicforest

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
systemctl is-enabled --quiet plasmalogin.service ||
    { echo "plasmalogin is not the display manager here; nothing done." >&2; exit 1; }

if [ "${1:-}" = "--undo" ]; then
    rm -rf "$FONT_DIR" "$WALL_DIR"
    rm -f "$CONF"
    if [ -f "$BACKUP/kdeglobals" ]; then
        install -o plasmalogin -g plasmalogin -m 644 "$BACKUP/kdeglobals" "$GREETER_GLOBALS"
    else
        rm -f "$GREETER_GLOBALS"
    fi
    fc-cache -f
    echo "Removed. Backup left in $BACKUP."
    exit 0
fi

# Back up once, so re-running never overwrites the original state.
if [ ! -d "$BACKUP" ]; then
    mkdir -p "$BACKUP/plasmalogin.conf.d"
    cp -a /etc/plasmalogin.conf.d/. "$BACKUP/plasmalogin.conf.d/"
    [ -f "$GREETER_GLOBALS" ] && cp -a "$GREETER_GLOBALS" "$BACKUP/kdeglobals"
    echo "Backup saved to $BACKUP"
fi

install -d -m 755 "$FONT_DIR" "$WALL_DIR"
install -m 644 "$SRC"/fonts/*.otf "$FONT_DIR/"
install -m 644 "$SRC/wallpaper/forest-triangle-nordic.png" "$WALL_DIR/"
install -m 644 "$SRC/10-nordicforest.conf" "$CONF"
install -d -o plasmalogin -g plasmalogin -m 755 "$GREETER_HOME/.config"
install -o plasmalogin -g plasmalogin -m 644 "$SRC/greeter-kdeglobals" "$GREETER_GLOBALS"
fc-cache -f "$FONT_DIR"
command -v restorecon >/dev/null &&
    restorecon -R "$FONT_DIR" "$WALL_DIR" "$CONF" "$GREETER_HOME/.config"

echo "Done. Log out or reboot to see the new login screen."
