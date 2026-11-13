# Pine Cabin rice

A dark, warm desktop rice for **MangoWM** and **KDE Plasma**, themed after a pine forest cabin at night.
Deep pine greens, a cedar accent and soft glass panels. Both desktops share one palette.

## Palette

| Role | Colour |
|---|---|
| Background | `#141815` |
| Background alt | `#1c221d` |
| Surface | `#2b352c` |
| Surface high | `#3d4a3c` |
| Text | `#c8d0c2` |
| Dim text | `#869180` |
| Pine (focus) | `#7f9a6e` |
| Cedar (accent) | `#c88a52` |
| Urgent | `#b5574a` |

## What's inside

```
config/
  mango/        MangoWM config, keybinds, window rules
  mangobar/     status bar
  kitty/        terminal + pine-cabin theme
  fish/         shell
  starship.toml prompt
  nvim/         Neovim (LazyVim)
  rofi/         launcher (Super+Space), translucent pine-cabin theme
  waybar/ mako/ notifications and bar
  fastfetch/ cava/ btop/
  Kvantum/      Qt theme
  gtk-3.0/ gtk-4.0/
  kde/          Plasma settings (colours, KWin, shortcuts, panels, Konsole)
local/share/
  plasma/       look-and-feel, desktop theme, plasmoids, wallpapers
  color-schemes/ konsole/ aurorae/
  mangowm-mod/  bar colours for mangowm-mod
  rice-sddm/    login screen theme + install script
  rice-plymouth/ boot splash + install script
local/bin/      helper scripts (screenshots, float toggle, focus, autostart…)
src/mango-ripple/ focus "ripple" animation for Mango (Rust)
```

## Keybinds (Mango)

| Keys | Action |
|---|---|
| Super+Space | Launcher (rofi) |
| Super+W | Browser |
| Super+H | Toggle floating |
| Print / Super+Shift+S | Screenshot a region |
| Super+Print / Super+Shift+P | Screenshot the whole screen |

The full list is in `config/mango/config.conf`.

## Install

Back up your own configs first. `install.sh` copies everything into place and moves any file it would replace to `~/.config/rice-backup-<date>/`.

```sh
git clone https://github.com/danielaufnahme-cmd/pine-cabin-rice.git
cd pine-cabin-rice
./install.sh
```

Optional extras, which need root:

```sh
sudo ~/.local/share/rice-sddm/install-sddm.sh                     # login screen
sudo ~/.local/share/rice-plymouth/install-plymouth-pinecabin.sh   # boot splash
```

Build the focus ripple:

```sh
cd src/mango-ripple && cargo build --release
cp target/release/mango-ripple ~/.local/bin/mango-monitor-ripple
```

## Needs

MangoWM, KDE Plasma 6, kitty, fish, starship, rofi, mako, fastfetch, btop, cava, Kvantum, Neovim, grim + slurp + wl-copy (screenshots).
Font: Monaspice (Monaspace Nerd Font).

Mango config lines have to stay under 255 bytes, or Mango ignores them.

---

Put together with help from Claude (Anthropic).
