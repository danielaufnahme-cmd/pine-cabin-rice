//! mango-monitor-ripple <output>: one wave from the centre of the focused
//! window on that monitor, growing into the window's rounded border and
//! fading out there, on a click-through overlay; then exits.
//! mango-monitor-ripple --render-frames DIR: writes sample frames as PNG and
//! times the drawing, without Wayland, to check the look.

mod colour;
mod ripple;

use std::os::fd::{AsFd, FromRawFd, OwnedFd};
use std::process::Command;
use std::time::{Duration, Instant};

use wayland_protocols::wp::presentation_time::client::{wp_presentation, wp_presentation_feedback};

use wayland_client::protocol::{
    wl_buffer, wl_callback, wl_compositor, wl_output, wl_region, wl_registry, wl_shm, wl_shm_pool,
    wl_surface,
};
use wayland_client::{delegate_noop, Connection, Dispatch, QueueHandle};
use wayland_protocols_wlr::layer_shell::v1::client::{zwlr_layer_shell_v1, zwlr_layer_surface_v1};
use zwlr_layer_surface_v1::{Anchor, KeyboardInteractivity};

/// Whatever happens, the process is gone after this.
const HARD_TIMEOUT: Duration = Duration::from_millis(1000);
const BUFFERS: usize = 3;
/// The wave's stroke at the start, in logical pixels; it thins to the
/// focus border width as it lands.
const STROKE_START: f32 = 7.0;
/// Without a border width (no window): the stroke it lands with.
const STROKE_END: f32 = 2.0;
/// Longest motion-blur trail, in logical pixels.
const MAX_TRAIL: f32 = 140.0;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.as_slice() {
        [flag, dir] if flag == "--render-frames" => render_frames(dir),
        [name] if !name.starts_with('-') => {
            std::thread::spawn(|| {
                std::thread::sleep(HARD_TIMEOUT);
                std::process::exit(0);
            });
            if let Err(e) = run(name) {
                eprintln!("mango-monitor-ripple: {e}");
                std::process::exit(1);
            }
        }
        _ => {
            eprintln!("usage: mango-monitor-ripple <output-name> | --render-frames DIR");
            std::process::exit(2);
        }
    }
}

/// Where the wave ends on the surface, from the window rect and border look.
fn target(w: usize, h: usize, scale: f32, look: &colour::Look, window: bool) -> ripple::Target {
    let border = look.border_px * scale;
    // a window: ride its border's centre line; no window: the monitor edges
    let (inset, radius, end) = if window && border > 0.0 {
        (border / 2.0, (look.border_radius * scale - border / 2.0).max(0.0), border)
    } else {
        (STROKE_END * scale / 2.0, 0.0, STROKE_END * scale)
    };
    ripple::Target {
        w,
        h,
        radius,
        inset,
        stroke_start: STROKE_START * scale,
        stroke_end: end,
        max_trail: MAX_TRAIL * scale,
    }
}

// ---- offscreen check ----

fn render_frames(dir: &str) {
    let look = colour::look();
    println!("look: {look:?}");
    // a monitor like DP-4 with a tiled window like the one on it now
    let (mw, mh) = (2560usize, 1440usize);
    let (wx, wy, ww, wh) = (10usize, 44usize, 1405usize, 1386usize);
    let t = target(ww, wh, 1.0, &look, true);
    let mut buf = vec![0u8; ww * wh * 4];

    std::fs::create_dir_all(dir).expect("cannot create the frame directory");
    let desk = image::Rgb([16u8, 20, 18]);
    let win = image::Rgb([30u8, 36, 33]);
    for pct in [10u32, 25, 50, 75, 90] {
        let ms = pct as f32 / 100.0 * ripple::DURATION_MS;
        buf.fill(0);
        if let Some(s) = ripple::shape(&t, ms) {
            ripple::draw(&mut buf, ww, wh, &s, look.rgb);
        }
        let mut out = image::RgbImage::from_pixel(mw as u32, mh as u32, desk);
        for y in 0..wh {
            for x in 0..ww {
                let src = &buf[(y * ww + x) * 4..(y * ww + x) * 4 + 4];
                let a = src[3] as f32 / 255.0;
                let px = out.get_pixel_mut((wx + x) as u32, (wy + y) as u32);
                // premultiplied "over" the window
                for (c, (s, bg)) in px.0.iter_mut().zip([src[2], src[1], src[0]].into_iter().zip(win.0)) {
                    *c = (s as f32 + bg as f32 * (1.0 - a)).round().min(255.0) as u8;
                }
            }
        }
        let path = format!("{dir}/v2-frame-{pct:03}pct.png");
        out.save(&path).expect("cannot write a frame");
        println!("{path}");
        if pct == 10 || pct == 75 {
            // a piece of the ring at full size, x8: soft edges, trail, fit
            let (cx, cy) = if pct == 75 {
                (wx - 6, wy - 6)
            } else {
                let s = ripple::shape(&t, ms).expect("inside the effect");
                ((wx as f32 + s.cx - 30.0) as usize, (wy as f32 + s.cy - s.hy - 20.0) as usize)
            };
            let crop = image::imageops::crop_imm(&out, cx as u32, cy as u32, 60, 60).to_image();
            let big = image::imageops::resize(&crop, 480, 480, image::imageops::FilterType::Nearest);
            let path = format!("{dir}/v2-zoom-{pct:03}pct-x8.png");
            big.save(&path).expect("cannot write the corner crop");
            println!("{path}");
        }
    }

    // timing: every frame of a 240 Hz run, clear old ring + draw new one
    let step = 1000.0 / 240.0;
    let mut times = Vec::new();
    let mut prev: Option<ripple::Shape> = None;
    buf.fill(0);
    for _ in 0..20 {
        let mut ms = 0.0;
        while let Some(s) = ripple::shape(&t, ms) {
            let start = Instant::now();
            if let Some(p) = prev {
                ripple::clear(&mut buf, ww, wh, &p);
            }
            ripple::draw(&mut buf, ww, wh, &s, look.rgb);
            let mut rects = 0;
            ripple::damage(&s, ww, wh, |_, _, _, _| rects += 1);
            times.push(start.elapsed().as_secs_f64() * 1000.0);
            std::hint::black_box(rects);
            prev = Some(s);
            ms += step;
        }
    }
    times.sort_by(f64::total_cmp);
    let avg = times.iter().sum::<f64>() / times.len() as f64;
    println!(
        "draw per frame ({} frames, {ww}x{wh}): avg {avg:.3} ms, p99 {:.3} ms, max {:.3} ms",
        times.len(),
        times[times.len() * 99 / 100],
        times[times.len() - 1]
    );
}

// ---- where to play ----

/// Logical rect (x, y, w, h) on the output.
type Rect = (i32, i32, i32, i32);

fn mmsg(what: &str) -> Option<String> {
    let out = Command::new("mmsg").args(["get", what]).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

/// The raw value after `"key":` in flat JSON (number, bool or string).
fn field<'a>(json: &'a str, key: &str) -> Option<&'a str> {
    let pat = format!("\"{key}\":");
    let rest = &json[json.find(&pat)? + pat.len()..];
    if let Some(s) = rest.strip_prefix('"') {
        return s.split('"').next();
    }
    let end = rest.find([',', '}', ']']).unwrap_or(rest.len());
    Some(rest[..end].trim())
}

fn int(json: &str, key: &str) -> Option<i32> {
    field(json, key)?.parse::<f64>().ok().map(|v| v.round() as i32)
}

/// One monitor's object out of `mmsg get all-monitors`.
fn monitor<'a>(all: &'a str, name: &str) -> Option<&'a str> {
    let start = all.find(&format!("\"name\":\"{name}\""))?;
    let rest = &all[start..];
    let end = rest[1..].find("{\"name\":").map_or(rest.len(), |i| i + 1);
    Some(&rest[..end])
}

/// The focused window's rect relative to the output, clipped to it, or the
/// whole output when no window on it has focus.
fn focus_rect(name: &str, monitors: &str, client: Option<&str>) -> Option<(Rect, bool)> {
    let mon = monitor(monitors, name)?;
    let (mx, my) = (int(mon, "x")?, int(mon, "y")?);
    let (mw, mh) = (int(mon, "width")?, int(mon, "height")?);
    let whole = ((0, 0, mw, mh), false);
    let Some(c) = client else { return Some(whole) };
    if field(c, "monitor") != Some(name)
        || field(c, "is_visible") == Some("false")
        || field(c, "is_minimized") == Some("true")
    {
        return Some(whole);
    }
    let (Some(x), Some(y), Some(w), Some(h)) =
        (int(c, "x"), int(c, "y"), int(c, "width"), int(c, "height"))
    else {
        return Some(whole);
    };
    let (x0, y0) = ((x - mx).max(0), (y - my).max(0));
    let (x1, y1) = ((x - mx + w).min(mw), (y - my + h).min(mh));
    if x1 - x0 < 8 || y1 - y0 < 8 {
        return Some(whole);
    }
    Some(((x0, y0, x1 - x0, y1 - y0), true))
}

// ---- overlay ----

struct Output {
    wl: wl_output::WlOutput,
    name: Option<String>,
    scale: i32,
    refresh_mhz: i32,
}

struct Buffer {
    wl: wl_buffer::WlBuffer,
    offset: usize,
    busy: bool,
    /// the ring this buffer still holds, cleared before reuse
    drawn: Option<ripple::Shape>,
}

#[derive(Default)]
struct State {
    compositor: Option<wl_compositor::WlCompositor>,
    shm: Option<wl_shm::WlShm>,
    layer_shell: Option<zwlr_layer_shell_v1::ZwlrLayerShellV1>,
    outputs: Vec<Output>,
    surface: Option<wl_surface::WlSurface>,
    size: (usize, usize),
    scale: i32,
    look: Option<colour::Look>,
    window: bool,
    target: Option<ripple::Target>,
    map: Option<(*mut u8, usize)>,
    buffers: Vec<Buffer>,
    /// the ring on screen now (to damage when it moves)
    shown: Option<ripple::Shape>,
    presentation: Option<wp_presentation::WpPresentation>,
    pacer: Pacer,
    done: bool,
}

/// Decides the time each frame will be on screen, so the motion follows the
/// monitor's vblank grid, not the moment this process got to run (which
/// jitters when the CPU is busy).
struct Pacer {
    /// clock of the presentation timestamps
    clock: libc::clockid_t,
    /// last time a frame of ours reached the screen (ns)
    presented: Option<i64>,
    /// refresh period (ns): from presentation feedback, else the output mode
    period: i64,
    /// screen time of the first frame, and of the latest one drawn (ns)
    start: Option<i64>,
    last: i64,
}

impl Default for Pacer {
    fn default() -> Self {
        Pacer {
            clock: libc::CLOCK_MONOTONIC,
            presented: None,
            period: 1_000_000_000 / 240,
            start: None,
            last: 0,
        }
    }
}

impl Pacer {
    fn now(&self) -> i64 {
        let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
        unsafe { libc::clock_gettime(self.clock, &mut ts) };
        ts.tv_sec * 1_000_000_000 + ts.tv_nsec
    }

    /// Milliseconds into the effect for the frame drawn now: the next vblank
    /// after `now` on the grid of the last presentation.
    fn next(&mut self, now: i64) -> f32 {
        let at = match self.presented {
            Some(p) if now >= p => p + ((now - p) / self.period + 1) * self.period,
            _ => now + self.period,
        };
        // never repeat or go back in time
        let at = if self.start.is_some() && at <= self.last { self.last + self.period } else { at };
        let start = *self.start.get_or_insert(at);
        self.last = at;
        (at - start) as f32 / 1e6
    }
}

fn run(name: &str) -> Result<(), String> {
    let monitors = mmsg("all-monitors").unwrap_or_default();
    let client = mmsg("focusing-client");
    let rect = focus_rect(name, &monitors, client.as_deref());
    let mut state = State { look: Some(colour::look()), scale: 1, ..Default::default() };
    let conn = Connection::connect_to_env().map_err(|e| format!("no Wayland: {e}"))?;
    let mut queue = conn.new_event_queue();
    let qh = queue.handle();
    conn.display().get_registry(&qh, ());
    // first round binds the globals, second gets the output names
    for _ in 0..2 {
        queue.roundtrip(&mut state).map_err(|e| e.to_string())?;
    }

    let (Some(compositor), Some(layer_shell)) = (state.compositor.clone(), state.layer_shell.clone())
    else {
        return Err("compositor lacks wl_compositor or wlr-layer-shell".into());
    };
    if state.shm.is_none() {
        return Err("compositor lacks wl_shm".into());
    }
    let out = state
        .outputs
        .iter()
        .find(|o| o.name.as_deref() == Some(name))
        .ok_or_else(|| format!("no output named {name}"))?;
    let (output, scale) = (out.wl.clone(), out.scale.max(1));
    state.scale = scale;
    if out.refresh_mhz > 0 {
        state.pacer.period = 1_000_000_000_000 / out.refresh_mhz as i64;
    }

    let surface = compositor.create_surface(&qh, ());
    surface.set_buffer_scale(scale);
    // empty input region: every click goes through
    let region = compositor.create_region(&qh, ());
    surface.set_input_region(Some(&region));
    region.destroy();
    let layer = layer_shell.get_layer_surface(
        &surface,
        Some(&output),
        zwlr_layer_shell_v1::Layer::Overlay,
        "mango-ripple".into(),
        &qh,
        (),
    );
    // only as big as the window: small buffers, small uploads
    match rect {
        Some(((x, y, w, h), window)) => {
            state.window = window;
            layer.set_size(w as u32, h as u32);
            layer.set_anchor(Anchor::Top | Anchor::Left);
            layer.set_margin(y, 0, 0, x);
        }
        None => {
            layer.set_size(0, 0);
            layer.set_anchor(Anchor::Top | Anchor::Bottom | Anchor::Left | Anchor::Right);
        }
    }
    layer.set_exclusive_zone(-1);
    layer.set_keyboard_interactivity(KeyboardInteractivity::None);
    surface.commit();
    state.surface = Some(surface);

    while !state.done {
        queue.blocking_dispatch(&mut state).map_err(|e| e.to_string())?;
    }
    let _ = queue.roundtrip(&mut state);
    Ok(())
}

impl State {
    /// One shm pool holding BUFFERS frames of the configured size.
    fn allocate(&mut self, qh: &QueueHandle<State>) -> Result<(), String> {
        let (w, h) = self.size;
        let frame = w * h * 4;
        let len = frame * BUFFERS;
        let fd = unsafe { libc::memfd_create(c"mango-ripple".as_ptr(), libc::MFD_CLOEXEC) };
        if fd < 0 {
            return Err("memfd_create failed".into());
        }
        let fd = unsafe { OwnedFd::from_raw_fd(fd) };
        let ptr = unsafe {
            use std::os::fd::AsRawFd;
            if libc::ftruncate(fd.as_raw_fd(), len as libc::off_t) < 0 {
                return Err("ftruncate failed".into());
            }
            libc::mmap(
                std::ptr::null_mut(),
                len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED | libc::MAP_POPULATE, // no page faults mid-animation
                fd.as_raw_fd(),
                0,
            )
        };
        if ptr == libc::MAP_FAILED {
            return Err("mmap failed".into());
        }
        let shm = self.shm.as_ref().expect("checked in run");
        let pool = shm.create_pool(fd.as_fd(), len as i32, qh, ());
        for i in 0..BUFFERS {
            let offset = i * frame;
            let wl = pool.create_buffer(
                offset as i32,
                w as i32,
                h as i32,
                (w * 4) as i32,
                wl_shm::Format::Argb8888,
                qh,
                i,
            );
            self.buffers.push(Buffer { wl, offset, busy: false, drawn: None });
        }
        pool.destroy();
        self.map = Some((ptr as *mut u8, len));
        Ok(())
    }

    /// Draws the frame for now and asks for the next one. Only the old and
    /// new ring are touched and damaged; the rest of each buffer stays clear.
    fn frame(&mut self, qh: &QueueHandle<State>) {
        let Some(surface) = self.surface.clone() else { return };
        let Some(target) = self.target else { return };
        let now = self.pacer.now();
        let t = self.pacer.next(now);
        let Some(shape) = ripple::shape(&target, t) else {
            self.done = true;
            return;
        };
        let Some(i) = self.buffers.iter().position(|b| !b.busy) else {
            // all held by the compositor: try again next frame
            surface.frame(qh, ());
            surface.commit();
            return;
        };
        let (w, h) = self.size;
        let (ptr, _) = self.map.expect("allocated before drawing");
        let buf = unsafe { std::slice::from_raw_parts_mut(ptr.add(self.buffers[i].offset), w * h * 4) };
        let first = self.shown.is_none();
        let b = &mut self.buffers[i];
        if let Some(old) = b.drawn.take() {
            ripple::clear(buf, w, h, &old);
        }
        let rgb = self.look.map_or(colour::DEFAULT.rgb, |l| l.rgb);
        ripple::draw(buf, w, h, &shape, rgb);
        b.drawn = Some(shape);
        b.busy = true;
        surface.attach(Some(&b.wl), 0, 0);
        let mut damage = |x, y, dw, dh| surface.damage_buffer(x, y, dw, dh);
        if first {
            damage(0, 0, w as i32, h as i32);
        } else {
            if let Some(old) = self.shown {
                ripple::damage(&old, w, h, &mut damage);
            }
            ripple::damage(&shape, w, h, &mut damage);
        }
        self.shown = Some(shape);
        surface.frame(qh, ());
        if let Some(p) = &self.presentation {
            p.feedback(&surface, qh, ());
        }
        surface.commit();
    }
}

impl Dispatch<wl_registry::WlRegistry, ()> for State {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        let wl_registry::Event::Global { name, interface, version } = event else { return };
        match interface.as_str() {
            "wl_compositor" => state.compositor = Some(registry.bind(name, version.min(4), qh, ())),
            "wl_shm" => state.shm = Some(registry.bind(name, 1, qh, ())),
            "zwlr_layer_shell_v1" => {
                state.layer_shell = Some(registry.bind(name, version.min(4), qh, ()))
            }
            "wp_presentation" => {
                state.presentation = Some(registry.bind(name, 1, qh, ()))
            }
            "wl_output" if version >= 4 => {
                let i = state.outputs.len();
                let wl = registry.bind(name, 4, qh, i);
                state.outputs.push(Output { wl, name: None, scale: 1, refresh_mhz: 0 });
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_output::WlOutput, usize> for State {
    fn event(
        state: &mut Self,
        _: &wl_output::WlOutput,
        event: wl_output::Event,
        i: &usize,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            wl_output::Event::Name { name } => state.outputs[*i].name = Some(name),
            wl_output::Event::Scale { factor } => state.outputs[*i].scale = factor,
            wl_output::Event::Mode { flags, refresh, .. }
                if refresh > 0
                    && flags.into_result().is_ok_and(|f| f.contains(wl_output::Mode::Current)) =>
            {
                state.outputs[*i].refresh_mhz = refresh;
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_layer_surface_v1::ZwlrLayerSurfaceV1, ()> for State {
    fn event(
        state: &mut Self,
        layer: &zwlr_layer_surface_v1::ZwlrLayerSurfaceV1,
        event: zwlr_layer_surface_v1::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match event {
            zwlr_layer_surface_v1::Event::Configure { serial, width, height } => {
                layer.ack_configure(serial);
                let s = state.scale as usize;
                let size = (width as usize * s, height as usize * s);
                if state.buffers.is_empty() && size.0 > 0 && size.1 > 0 {
                    state.size = size;
                    let look = state.look.unwrap_or(colour::DEFAULT);
                    state.target =
                        Some(target(size.0, size.1, state.scale as f32, &look, state.window));
                    if let Err(e) = state.allocate(qh) {
                        eprintln!("mango-monitor-ripple: {e}");
                        state.done = true;
                        return;
                    }
                    state.frame(qh);
                }
            }
            zwlr_layer_surface_v1::Event::Closed => state.done = true,
            _ => {}
        }
    }
}

impl Dispatch<wl_callback::WlCallback, ()> for State {
    fn event(
        state: &mut Self,
        _: &wl_callback::WlCallback,
        event: wl_callback::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_callback::Event::Done { .. } = event {
            state.frame(qh);
        }
    }
}

impl Dispatch<wl_buffer::WlBuffer, usize> for State {
    fn event(
        state: &mut Self,
        _: &wl_buffer::WlBuffer,
        event: wl_buffer::Event,
        i: &usize,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_buffer::Event::Release = event {
            state.buffers[*i].busy = false;
        }
    }
}

impl Dispatch<wp_presentation::WpPresentation, ()> for State {
    fn event(
        state: &mut Self,
        _: &wp_presentation::WpPresentation,
        event: wp_presentation::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wp_presentation::Event::ClockId { clk_id } = event {
            state.pacer.clock = clk_id as libc::clockid_t;
        }
    }
}

impl Dispatch<wp_presentation_feedback::WpPresentationFeedback, ()> for State {
    fn event(
        state: &mut Self,
        _: &wp_presentation_feedback::WpPresentationFeedback,
        event: wp_presentation_feedback::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wp_presentation_feedback::Event::Presented {
            tv_sec_hi, tv_sec_lo, tv_nsec, refresh, ..
        } = event
        {
            let secs = ((tv_sec_hi as i64) << 32) | tv_sec_lo as i64;
            let at = secs * 1_000_000_000 + tv_nsec as i64;
            state.pacer.presented = Some(state.pacer.presented.map_or(at, |p| p.max(at)));
            if refresh > 0 {
                state.pacer.period = refresh as i64;
            }
        }
    }
}

delegate_noop!(State: ignore wl_compositor::WlCompositor);
delegate_noop!(State: ignore wl_shm::WlShm);
delegate_noop!(State: ignore wl_shm_pool::WlShmPool);
delegate_noop!(State: ignore wl_surface::WlSurface);
delegate_noop!(State: ignore wl_region::WlRegion);
delegate_noop!(State: ignore zwlr_layer_shell_v1::ZwlrLayerShellV1);

#[cfg(test)]
mod tests {
    use super::*;

    const MONITORS: &str = r#"{"monitors":[{"name":"HDMI-A-2","active":false,"x":0,"y":0,"width":2560,"height":1440,"scale":1,"tags":[{"index":1,"is_active":true}],"active_client":{"id":4,"title":"a, b","appid":"kitty"}},{"name":"DP-4","active":true,"x":2560,"y":0,"width":2560,"height":1440,"scale":1,"tags":[{"index":1}],"active_client":{"id":10,"title":"~","appid":"kitty"}}]}"#;
    const CLIENT: &str = r#"{"id":10,"title":"~","appid":"kitty","monitor":"DP-4","tags":[1],"is_visible":true,"is_focused":true,"is_minimized":false,"x":2570,"y":44,"width":1405,"height":1386,"scroller_proportion":0.9}"#;

    #[test]
    fn window_rect_is_relative_to_its_monitor() {
        assert_eq!(focus_rect("DP-4", MONITORS, Some(CLIENT)), Some(((10, 44, 1405, 1386), true)));
    }

    #[test]
    fn no_window_on_that_monitor_falls_back_to_the_monitor() {
        assert_eq!(
            focus_rect("HDMI-A-2", MONITORS, Some(CLIENT)),
            Some(((0, 0, 2560, 1440), false))
        );
        assert_eq!(focus_rect("DP-4", MONITORS, None), Some(((0, 0, 2560, 1440), false)));
        assert_eq!(focus_rect("DP-4", MONITORS, Some("{}")), Some(((0, 0, 2560, 1440), false)));
        assert_eq!(focus_rect("DP-9", MONITORS, Some(CLIENT)), None);
    }

    #[test]
    fn window_partly_off_the_monitor_is_clipped() {
        let c = CLIENT.replace("\"x\":2570", "\"x\":4000");
        assert_eq!(focus_rect("DP-4", MONITORS, Some(&c)), Some(((1440, 44, 1120, 1386), true)));
    }

    #[test]
    fn target_rides_the_border_centre_line() {
        let look = colour::Look { rgb: [0, 0, 0], alpha: 1.0, border_radius: 10.0, border_px: 2.0 };
        let t = target(1405, 1386, 1.0, &look, true);
        assert_eq!((t.inset, t.radius, t.stroke_start, t.stroke_end), (1.0, 9.0, 7.0, 2.0));
        let t = target(2560, 1440, 1.0, &look, false);
        assert_eq!((t.inset, t.radius), (1.0, 0.0));
    }
}

#[cfg(test)]
mod pacer_tests {
    use super::Pacer;

    const P: i64 = 4_166_667;

    #[test]
    fn frames_land_on_the_vblank_grid_even_when_woken_late() {
        let mut p = Pacer { period: P, ..Default::default() };
        assert_eq!(p.next(1_000), 0.0); // first frame is t = 0
        p.presented = Some(1_000 + P);
        // woken 0.3 ms or 3.5 ms after the vblank: same next vblank
        let a = p.next(1_000 + P + 300_000);
        assert!((a - P as f32 / 1e6).abs() < 1e-3, "{a}");
        p.presented = Some(1_000 + 2 * P);
        let b = p.next(1_000 + 2 * P + 3_500_000);
        assert!((b - 2.0 * P as f32 / 1e6).abs() < 1e-3, "{b}");
        // a missed vblank skips ahead instead of slowing the motion down
        let c = p.next(1_000 + 4 * P + 100_000);
        assert!((c - 4.0 * P as f32 / 1e6).abs() < 1e-3, "{c}");
    }

    #[test]
    fn never_goes_back_in_time() {
        let mut p = Pacer { period: P, ..Default::default() };
        let a = p.next(10 * P);
        p.presented = Some(5 * P); // stale feedback
        let b = p.next(10 * P + 1);
        assert!(b > a);
    }
}
