#!/bin/bash
# Install (or undo) the PineCabin Plymouth boot theme.
#
#   sudo ./install-plymouth-pinecabin.sh          install + set as default
#   sudo ./install-plymouth-pinecabin.sh --undo   restore the previous theme
#
# Both directions rebuild the initramfs (plymouth-set-default-theme -R),
# which takes a minute or two. Running it twice is harmless.
set -euo pipefail

THEME=pinecabin
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$THEME"
DEST=/usr/share/plymouth/themes/$THEME
STATE_DIR=/var/lib/rice-plymouth
# Own state file, so the NordicForest installer's saved theme is never overwritten.
PREV_FILE=$STATE_DIR/previous-theme-$THEME

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
command -v plymouth-set-default-theme >/dev/null || die "plymouth is not installed"
[[ -e /usr/lib64/plymouth/two-step.so || -e /usr/lib/plymouth/two-step.so ]] \
    || die "plymouth two-step plugin missing (dnf install plymouth-plugin-two-step)"

current=$(plymouth-set-default-theme)

if [[ ${1:-} == --undo ]]; then
    prev=$(cat "$PREV_FILE" 2>/dev/null || echo bgrt)
    if [[ $current == "$prev" ]]; then
        echo "Theme is already '$prev'; nothing to undo."
        exit 0
    fi
    echo "Restoring Plymouth theme '$prev' (was '$current')."
    echo "Rebuilding the initramfs, this can take a minute or two..."
    plymouth-set-default-theme -R "$prev"
    echo "Done. '$DEST' is left in place; remove it by hand if you want."
    exit 0
fi

[[ -f $SRC/$THEME.plymouth ]] || die "theme files not found in $SRC"

# Remember the theme we replace, but never overwrite it with our own name.
mkdir -p "$STATE_DIR"
if [[ $current != "$THEME" ]]; then
    echo "$current" > "$PREV_FILE"
    echo "Saved current theme '$current' to $PREV_FILE"
fi

echo "Copying theme to $DEST"
install -d -m 755 "$DEST"
install -m 644 "$SRC"/*.png "$SRC/$THEME.plymouth" "$DEST/"

if [[ $current == "$THEME" ]]; then
    echo "Theme already active; rebuilding initramfs to pick up any file changes..."
else
    echo "Setting '$THEME' as default."
    echo "Rebuilding the initramfs, this can take a minute or two..."
fi
plymouth-set-default-theme -R "$THEME"
echo "Done. Reboot to see it. Undo with: sudo $0 --undo"
