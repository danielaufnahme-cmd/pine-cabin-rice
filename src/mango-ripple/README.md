# mango-monitor-ripple

One wave (320 ms, mango's ease-out curve 0.22,1,0.36,1) from the centre of the
focused window, used by `~/.local/bin/mango-focusdir` when Super+arrow moves
focus to the other monitor. The ring starts as a circle, turns into the
window's rounded rectangle as it grows and fades out on its focus border.
It starts 7 px thick and thins to the border width; while fast it drags a
soft motion-blur trail (how far it moved in the last 10 ms, max 140 px).
Frame times follow wp_presentation feedback: each frame is drawn for the
next vblank on the grid of the last presentation, not for "now".

- `mango-monitor-ripple DP-4` — plays once on that output and exits.
  Window rect from `mmsg get focusing-client` (+ `all-monitors` for the
  monitor origin); no focused window on that output: the monitor edges.
  wlr-layer-shell OVERLAY surface sized to the window rect only, exclusive
  zone -1, no keyboard interactivity, empty input region (click-through).
  Frames are driven by frame callbacks; each frame clears the old ring and
  draws the new one in 3 reused buffers and damages only those strips.
  A watchdog ends the process after 1 s whatever happens.
- `mango-monitor-ripple --render-frames DIR` — writes sample frames as PNG
  and times the drawing, no Wayland needed (for checking the look).

Colour, border width and radius: `focus_color`, `border_px`, `border_radius`
from `~/.config/mango/config.conf` (following `source=`, last value wins).

Build and install:

    cargo build --release
    install -m 755 target/release/mango-monitor-ripple ~/.local/bin/
