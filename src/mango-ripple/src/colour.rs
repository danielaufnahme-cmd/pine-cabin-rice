//! The look of the focus border, read from ~/.config/mango/config.conf
//! (following `source=` lines, last value wins, like mango itself), so the
//! wave follows theme changes.

use std::fs;
use std::path::{Path, PathBuf};

pub type Rgb = [u8; 3];

/// Focus border look in logical pixels.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Look {
    pub rgb: Rgb,
    /// alpha of focus_color, 0..1
    pub alpha: f32,
    pub border_radius: f32,
    pub border_px: f32,
}

/// mango's own defaults for this rice: pine focus colour, radius 12, 2 px.
pub const DEFAULT: Look =
    Look { rgb: [0x7f, 0x9a, 0x6e], alpha: 1.0, border_radius: 12.0, border_px: 2.0 };

const MAX_SOURCE_DEPTH: usize = 4;

pub fn look() -> Look {
    let Some(home) = std::env::var_os("HOME") else { return DEFAULT };
    let dir = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| Path::new(&home).join(".config"))
        .join("mango");
    let mut look = DEFAULT;
    read(&dir.join("config.conf"), &mut look, 0);
    look
}

fn read(path: &Path, look: &mut Look, depth: usize) {
    let Ok(text) = fs::read_to_string(path) else { return };
    let dir = path.parent().unwrap_or(Path::new("/"));
    for line in text.lines() {
        let Some((key, value)) = line.trim().split_once('=') else { continue };
        let (key, value) = (key.trim(), value.trim());
        match key {
            "source" if depth < MAX_SOURCE_DEPTH => {
                read(&resolve(dir, value), look, depth + 1);
            }
            "focus_color" => {
                if let Some((rgb, alpha)) = parse_colour(value) {
                    look.rgb = rgb;
                    look.alpha = alpha;
                }
            }
            "border_radius" => {
                if let Ok(v) = value.parse::<f32>() {
                    look.border_radius = v.max(0.0);
                }
            }
            "border_px" => {
                if let Ok(v) = value.parse::<f32>() {
                    look.border_px = v.max(0.0);
                }
            }
            _ => {}
        }
    }
}

fn resolve(dir: &Path, value: &str) -> PathBuf {
    match value.strip_prefix("~/") {
        Some(rest) => Path::new(&std::env::var_os("HOME").unwrap_or_default()).join(rest),
        None => dir.join(value),
    }
}

/// `0xRRGGBBAA` (mango's format).
fn parse_colour(s: &str) -> Option<(Rgb, f32)> {
    let hex = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X"))?;
    if hex.len() != 8 {
        return None;
    }
    let v = u32::from_str_radix(hex, 16).ok()?;
    let [r, g, b, a] = v.to_be_bytes();
    Some(([r, g, b], a as f32 / 255.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_mango_colour() {
        assert_eq!(parse_colour("0x7f9a6eff"), Some(([0x7f, 0x9a, 0x6e], 1.0)));
        assert_eq!(parse_colour("7f9a6eff"), None);
        assert_eq!(parse_colour("0x7f9a6e"), None);
    }

    #[test]
    fn sourced_file_overrides_earlier_values() {
        let dir = std::env::temp_dir().join(format!("mango-ripple-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("config.conf"),
            "# c\nborder_radius=12\nfocus_color=0x112233ff\nsource=./mod.conf\nborder_px=3\n",
        )
        .unwrap();
        fs::write(dir.join("mod.conf"), "border_radius=10\nfocus_color=0x7f9a6e80\n").unwrap();
        let mut look = DEFAULT;
        read(&dir.join("config.conf"), &mut look, 0);
        assert_eq!(look.rgb, [0x7f, 0x9a, 0x6e]);
        assert!((look.alpha - 128.0 / 255.0).abs() < 1e-6);
        assert_eq!(look.border_radius, 10.0);
        assert_eq!(look.border_px, 3.0);
        let _ = fs::remove_file(dir.join("config.conf"));
        let _ = fs::remove_file(dir.join("mod.conf"));
        let _ = fs::remove_dir(&dir);
    }
}
