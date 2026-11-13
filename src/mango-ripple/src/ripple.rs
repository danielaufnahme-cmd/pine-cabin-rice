//! The wave: one ring that grows from the centre of the focused window,
//! turns from a circle into the window's rounded rectangle on the way and
//! fades out exactly on its focus border. It starts thick and thins to the
//! border width as it lands; while it moves fast a soft motion-blur trail
//! follows it (toward the centre), shrinking to nothing as it settles.
//!
//! Only the pixels near the ring are touched: each row gets at most two
//! spans (the ring plus its trail), never the whole surface.

use crate::colour::Rgb;

/// Length of the whole effect.
pub const DURATION_MS: f32 = 320.0;
/// Same curve as mango's open/move animations.
const CURVE: [f32; 4] = [0.22, 1.0, 0.36, 1.0];
/// Strength of the stroke (the focus colour, slightly see-through).
const OPACITY: f32 = 0.85;
/// Share of the timeline spent fading in / where the fade-out starts.
const FADE_IN: f32 = 0.05;
const FADE_OUT_FROM: f32 = 0.55;
/// Share of the timeline over which the stroke thins to the border width.
const THIN_BY: f32 = 0.6;
/// "Shutter" of the motion blur: the trail is how far the ring moved in it.
const SHUTTER_MS: f32 = 10.0;
/// Strength of the trail right behind the ring (relative to the ring).
const TRAIL_ALPHA: f32 = 0.5;
/// Half the width of the soft edge of the ring, in pixels.
const SOFT: f32 = 0.8;

/// Where the wave ends, in buffer pixels: a `w`×`h` surface over the window.
#[derive(Clone, Copy, Debug)]
pub struct Target {
    pub w: usize,
    pub h: usize,
    /// corner radius of the border's centre line
    pub radius: f32,
    /// distance from the surface edge to the border's centre line
    pub inset: f32,
    /// stroke width at the start and when it lands
    pub stroke_start: f32,
    pub stroke_end: f32,
    /// longest motion trail
    pub max_trail: f32,
}

/// The ring at one moment: a rounded box around (cx, cy).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Shape {
    pub cx: f32,
    pub cy: f32,
    pub hx: f32,
    pub hy: f32,
    pub r: f32,
    /// half the stroke width
    pub half: f32,
    /// length of the motion trail inside the ring
    pub trail: f32,
    pub alpha: f32,
}

/// CSS-style cubic-bezier(x1, y1, x2, y2) easing.
pub fn ease(p: f32) -> f32 {
    let [x1, y1, x2, y2] = CURVE;
    let p = p.clamp(0.0, 1.0);
    let bez = |a: f32, b: f32, u: f32| {
        let v = 1.0 - u;
        3.0 * v * v * u * a + 3.0 * v * u * u * b + u * u * u
    };
    // x(u) is monotonic: bisection is exact enough after 24 rounds
    let (mut lo, mut hi) = (0.0f32, 1.0f32);
    for _ in 0..24 {
        let mid = 0.5 * (lo + hi);
        if bez(x1, x2, mid) < p {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    bez(y1, y2, 0.5 * (lo + hi))
}

fn lerp(a: f32, b: f32, k: f32) -> f32 {
    a + (b - a) * k
}

fn smoothstep(a: f32, b: f32, x: f32) -> f32 {
    let k = ((x - a) / (b - a)).clamp(0.0, 1.0);
    k * k * (3.0 - 2.0 * k)
}

/// Half sizes and corner radius of the ring at progress `p` (0..1).
fn geometry(t: &Target, p: f32) -> (f32, f32, f32) {
    let s = ease(p);
    let m = s * s; // circle early, the window's shape late
    let end_x = (t.w as f32 / 2.0 - t.inset).max(0.0);
    let end_y = (t.h as f32 / 2.0 - t.inset).max(0.0);
    let small = end_x.min(end_y);
    let hx = s * lerp(small, end_x, m);
    let hy = s * lerp(small, end_y, m);
    let round = hx.min(hy);
    let r = lerp(round, t.radius.min(small), m).clamp(0.0, round);
    (hx, hy, r)
}

/// The ring at `t_ms`, or None once the effect is over.
pub fn shape(t: &Target, t_ms: f32) -> Option<Shape> {
    let p = t_ms / DURATION_MS;
    if !(0.0..1.0).contains(&p) {
        return None;
    }
    let (hx, hy, r) = geometry(t, p);
    let (px, py, _) = geometry(t, ((t_ms - SHUTTER_MS) / DURATION_MS).max(0.0));
    let moved = (hx - px).max(hy - py).max(0.0);
    let stroke = lerp(t.stroke_start, t.stroke_end, smoothstep(0.0, THIN_BY, p));
    let half = stroke / 2.0;
    let fade_in = (p / FADE_IN).min(1.0);
    let fade_out = 1.0 - smoothstep(FADE_OUT_FROM, 1.0, p);
    Some(Shape {
        cx: t.w as f32 / 2.0,
        cy: t.h as f32 / 2.0,
        hx,
        hy,
        r,
        half,
        trail: moved.min(t.max_trail).min((hx.min(hy) - half).max(0.0)),
        alpha: OPACITY * fade_in * fade_out,
    })
}

/// Signed distance from (x, y) to the ring's centre line (negative inside).
fn distance(s: &Shape, x: f32, y: f32) -> f32 {
    let qx = (x - s.cx).abs() - (s.hx - s.r);
    let qy = (y - s.cy).abs() - (s.hy - s.r);
    let (ox, oy) = (qx.max(0.0), qy.max(0.0));
    (ox * ox + oy * oy).sqrt() + qx.max(qy).min(0.0) - s.r
}

/// Opacity (0..1, before `alpha`) at signed distance `d` from the ring.
fn coverage(s: &Shape, d: f32) -> f32 {
    // the ring: soft edges on both sides
    let ring = smoothstep(-SOFT, SOFT, s.half - d.abs());
    if d >= 0.0 || s.trail <= 0.0 {
        return ring;
    }
    // the trail: fades from the ring's inner edge to 0 over `trail` pixels
    let u = ((-d - s.half) / s.trail).clamp(0.0, 1.0);
    let k = 1.0 - u;
    ring.max(TRAIL_ALPHA * k * k)
}

/// How far outside / inside the centre line anything can be lit.
fn reach(s: &Shape) -> (f32, f32) {
    let out = s.half + SOFT + 1.0;
    (out, out + s.trail)
}

/// Half width of a rounded box (half sizes ax, ay, radius r) at height |y|.
fn half_width(ax: f32, ay: f32, r: f32, y: f32) -> Option<f32> {
    if ax < 0.0 || ay < 0.0 || y > ay {
        return None;
    }
    let straight = ay - r;
    if y <= straight {
        return Some(ax);
    }
    let dy = y - straight;
    Some(ax - r + (r * r - dy * dy).max(0.0).sqrt())
}

/// Calls `f(row, x0, x1)` for every pixel span (x0..x1) that can be lit.
fn spans(s: &Shape, w: usize, h: usize, mut f: impl FnMut(usize, usize, usize)) {
    let (eo, ei) = reach(s);
    let y0 = (s.cy - s.hy - eo - 1.0).floor().max(0.0) as usize;
    let y1 = ((s.cy + s.hy + eo + 1.0).ceil().max(0.0) as usize).min(h);
    let (ix, iy, ir) = (s.hx - ei, s.hy - ei, (s.r - ei).max(0.0));
    let clamp = |x: f32| (x.max(0.0) as usize).min(w);
    for y in y0..y1 {
        let dy = (y as f32 + 0.5 - s.cy).abs();
        let Some(outer) = half_width(s.hx + eo, s.hy + eo, s.r + eo, dy) else { continue };
        let inner = half_width(ix, iy, ir, dy).filter(|&v| v > 0.0);
        // pixel centres: x + 0.5; widen by a pixel each side, coverage decides
        let a = clamp((s.cx - outer - 1.5).floor());
        let d = clamp((s.cx + outer + 0.5).ceil());
        match inner {
            Some(inner) => {
                let b = clamp((s.cx - inner + 0.5).ceil());
                let c = clamp((s.cx + inner - 1.5).floor());
                if b < c {
                    f(y, a, b);
                    f(y, c, d);
                } else {
                    f(y, a, d);
                }
            }
            None => f(y, a, d),
        }
    }
}

/// Draws the ring into `buf` (ARGB8888 little endian, premultiplied,
/// stride `w * 4`). Only touches the ring's spans.
pub fn draw(buf: &mut [u8], w: usize, h: usize, s: &Shape, rgb: Rgb) {
    let a_max = s.alpha.clamp(0.0, 1.0);
    let [r, g, b] = rgb.map(|c| c as f32);
    spans(s, w, h, |y, x0, x1| {
        let py = y as f32 + 0.5;
        let row = &mut buf[y * w * 4..(y + 1) * w * 4];
        for x in x0..x1 {
            let a = coverage(s, distance(s, x as f32 + 0.5, py)) * a_max;
            let px = &mut row[x * 4..x * 4 + 4];
            px[0] = (b * a + 0.5) as u8;
            px[1] = (g * a + 0.5) as u8;
            px[2] = (r * a + 0.5) as u8;
            px[3] = (255.0 * a + 0.5) as u8;
        }
    });
}

/// Zeroes everything `draw` may have written for this shape.
pub fn clear(buf: &mut [u8], w: usize, h: usize, s: &Shape) {
    spans(s, w, h, |y, x0, x1| buf[(y * w + x0) * 4..(y * w + x1) * 4].fill(0));
}

/// Rows per damage rectangle.
const DAMAGE_ROWS: usize = 16;

/// Rectangles (x, y, w, h) covering every pixel the shape may touch:
/// per 16-row band one rect, or two when the ring's sides are apart.
pub fn damage(s: &Shape, w: usize, h: usize, mut f: impl FnMut(i32, i32, i32, i32)) {
    /// One band of rows: x extents of the left and right sides.
    struct Band {
        y0: usize,
        y1: usize,
        left: Option<(usize, usize)>,
        right: Option<(usize, usize)>,
    }
    fn grow(side: &mut Option<(usize, usize)>, x0: usize, x1: usize) {
        *side = Some(side.map_or((x0, x1), |(a, b)| (a.min(x0), b.max(x1))));
    }
    fn flush(band: &Band, f: &mut impl FnMut(i32, i32, i32, i32)) {
        let (y, hgt) = (band.y0 as i32, (band.y1 + 1 - band.y0) as i32);
        let mut rect = |(a, b): (usize, usize)| f(a as i32, y, (b - a) as i32, hgt);
        match (band.left, band.right) {
            (Some(l), Some(r)) if l.1 >= r.0 => rect((l.0.min(r.0), l.1.max(r.1))),
            (Some(l), Some(r)) => {
                rect(l);
                rect(r);
            }
            (Some(one), None) | (None, Some(one)) => rect(one),
            (None, None) => {}
        }
    }
    let mid = s.cx;
    let mut band: Option<Band> = None;
    spans(s, w, h, |y, x0, x1| {
        if x1 <= x0 {
            return;
        }
        if band.as_ref().is_some_and(|b| b.y0 / DAMAGE_ROWS != y / DAMAGE_ROWS) {
            flush(&band.take().unwrap(), &mut f);
        }
        let b = band.get_or_insert(Band { y0: y, y1: y, left: None, right: None });
        b.y1 = y;
        if x1 as f32 <= mid + 1.0 {
            grow(&mut b.left, x0, x1);
        } else if x0 as f32 >= mid - 1.0 {
            grow(&mut b.right, x0, x1);
        } else {
            grow(&mut b.left, x0, x1); // one span across the middle
        }
    });
    if let Some(b) = band {
        flush(&b, &mut f);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RGB: Rgb = [0x7f, 0x9a, 0x6e];

    fn target(w: usize, h: usize) -> Target {
        Target {
            w,
            h,
            radius: 9.0,
            inset: 1.0,
            stroke_start: 7.0,
            stroke_end: 2.0,
            max_trail: 140.0,
        }
    }

    #[test]
    fn ease_matches_the_curve_ends_and_is_monotonic() {
        assert!(ease(0.0).abs() < 1e-4);
        assert!((ease(1.0) - 1.0).abs() < 1e-4);
        let mut last = 0.0;
        for i in 0..=100 {
            let v = ease(i as f32 / 100.0);
            assert!(v + 1e-5 >= last, "not monotonic at {i}");
            last = v;
        }
        // strong ease-out: most of the way there by half time
        assert!(ease(0.5) > 0.9);
    }

    #[test]
    fn starts_as_a_thick_circle_and_ends_thin_on_the_border() {
        let t = target(1405, 1386);
        let early = shape(&t, 5.0).unwrap();
        assert!((early.hx - early.hy).abs() < 0.5, "{early:?}");
        assert!((early.r - early.hx.min(early.hy)).abs() < 1.0, "{early:?}");
        assert!(early.half > 3.3, "{early:?}");
        let late = shape(&t, DURATION_MS - 0.01).unwrap();
        assert!((late.hx - (1405.0 / 2.0 - 1.0)).abs() < 0.5, "{late:?}");
        assert!((late.hy - (1386.0 / 2.0 - 1.0)).abs() < 0.5, "{late:?}");
        assert!((late.r - 9.0).abs() < 0.1, "{late:?}");
        assert!((late.half - 1.0).abs() < 1e-4, "{late:?}");
        assert!(late.alpha < 0.01);
        assert!(shape(&t, DURATION_MS).is_none());
    }

    #[test]
    fn single_ring_grows_steadily_and_trail_shrinks_as_it_settles() {
        let t = target(1405, 1386);
        let mut last = 0.0;
        let mut last_trail = f32::MAX;
        for ms in (12..DURATION_MS as usize).step_by(4) {
            let s = shape(&t, ms as f32).unwrap();
            assert!(s.hx + 1e-4 >= last);
            // the trail only shrinks once the ring is out of the centre
            if ms > 40 {
                assert!(s.trail <= last_trail + 1e-3, "t={ms} {s:?}");
            }
            last = s.hx;
            last_trail = s.trail;
        }
        assert!(shape(&t, 40.0).unwrap().trail > 40.0);
        assert!(shape(&t, DURATION_MS - 1.0).unwrap().trail < 0.5);
    }

    #[test]
    fn trail_is_inside_and_fades_out() {
        let t = target(1405, 1386);
        let s = shape(&t, 40.0).unwrap();
        assert_eq!(coverage(&s, 0.0), 1.0);
        assert!(coverage(&s, s.half + SOFT + 0.01) < 1e-6); // nothing outside
        let near = coverage(&s, -(s.half + SOFT + 1.0));
        let far = coverage(&s, -(s.half + s.trail * 0.7));
        assert!(near > far && far > 0.0, "{near} {far}");
        assert_eq!(coverage(&s, -(s.half + s.trail + 0.01)), 0.0);
    }

    /// The span walk must not miss any lit pixel: compare with a full scan.
    #[test]
    fn spans_cover_every_lit_pixel() {
        let (w, h) = (300usize, 200usize);
        let t = target(w, h);
        for ms in [3.0, 12.0, 20.0, 45.0, 80.0, 150.0, 310.0] {
            let s = shape(&t, ms).unwrap();
            let mut fast = vec![0u8; w * h * 4];
            draw(&mut fast, w, h, &s, RGB);
            for y in 0..h {
                for x in 0..w {
                    let d = distance(&s, x as f32 + 0.5, y as f32 + 0.5);
                    let want = (255.0 * coverage(&s, d) * s.alpha + 0.5) as u8;
                    assert_eq!(fast[(y * w + x) * 4 + 3], want, "t={ms} at {x},{y}");
                }
            }
            // and clear() really empties it
            clear(&mut fast, w, h, &s);
            assert!(fast.iter().all(|&b| b == 0), "t={ms}");
        }
    }

    #[test]
    fn damage_covers_every_drawn_pixel() {
        let (w, h) = (300usize, 200usize);
        let t = target(w, h);
        for ms in [3.0, 12.0, 20.0, 45.0, 80.0, 150.0, 310.0] {
            let s = shape(&t, ms).unwrap();
            let mut buf = vec![0u8; w * h * 4];
            draw(&mut buf, w, h, &s, RGB);
            let mut covered = vec![false; w * h];
            let mut area = 0;
            damage(&s, w, h, |x, y, dw, dh| {
                area += dw * dh;
                for yy in y..y + dh {
                    for xx in x..x + dw {
                        covered[yy as usize * w + xx as usize] = true;
                    }
                }
            });
            for i in 0..w * h {
                if buf[i * 4 + 3] != 0 {
                    assert!(covered[i], "t={ms} pixel {} {} not damaged", i % w, i / w);
                }
            }
            // late frames damage only a thin frame, not the whole surface
            if ms > 100.0 {
                assert!(area < (w * h / 3) as i32, "t={ms} area {area}");
            }
        }
    }
}
