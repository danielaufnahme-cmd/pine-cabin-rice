#!/bin/sh
# Copy the Pine Cabin rice into place. Anything replaced is moved to a backup folder first.
set -e
cd "$(dirname "$0")"
BACKUP="$HOME/.config/rice-backup-$(date +%Y%m%d-%H%M%S)"

place() { # place <source> <destination>
  if [ -e "$2" ]; then
    mkdir -p "$BACKUP"
    mv "$2" "$BACKUP/"
  fi
  mkdir -p "$(dirname "$2")"
  cp -r "$1" "$2"
}

for item in config/*; do
  name=$(basename "$item")
  [ "$name" = kde ] && continue
  place "$item" "$HOME/.config/$name"
done
for item in config/kde/*; do
  place "$item" "$HOME/.config/$(basename "$item")"
done
for item in local/share/*; do
  place "$item" "$HOME/.local/share/$(basename "$item")"
done
mkdir -p "$HOME/.local/bin"
cp local/bin/* "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/"*

echo "Done. Replaced files are in: $BACKUP"
echo "Log out and back in (or restart Mango / plasmashell) to see it."
