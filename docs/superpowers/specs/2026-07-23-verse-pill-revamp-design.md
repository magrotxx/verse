# Verse 2.0 — floating lyric pill (design spec)

Decided with the user on 2026-07-23. Supersedes the notch-docked design in
CLAUDE.md (CLAUDE.md must be updated as part of implementation).

## Design revision A (2026-07-24) — SUPERSEDES conflicting lines below

User-decided refinements after seeing the direction. Where this section
conflicts with anything later in the spec, THIS section wins:

1. **Material:** the pill is translucent BLACK (neutral dark glass at ~55-65%
   opacity), no album-hue wash on the pill, no album-accent glow. Shadow is
   black, soft and light (e.g. opacity ~0.25, radius ~10, y 3) — the
   Raycast-like "techie" look. Album color survives ONLY in lyric text tints
   inside the pill and popup content.
2. **Dynamic width:** the pill's width follows the current line — it expands
   and contracts per lyric with a spring, sized to the text plus padding,
   clamped to [ball diameter, pillMaxWidth]. The old "fixed width while a
   song plays" rule is DEAD. Chunking applies only to lines wider than
   pillMaxWidth. While paused, width freezes with the frozen lyric.
3. **Idle ball:** when NO music is playing the pill does not disappear — it
   contracts into a small circular ball (~30pt) showing a translucent
   music-note SF Symbol (~40% white). The ball is draggable but clicks are
   inert (no popup, no action). Clicking works only while a song is loaded.
   The first-run demo/tooltip still applies, anchored to the ball.
4. **Edge-anchored growth:** width changes respect where the user parked it.
   If the ball/pill sits in the right third of the screen, the RIGHT edge is
   the anchor and growth extends leftward; left third → left edge anchored,
   growth extends rightward; middle third → centered symmetric growth. The
   persisted position is the anchor point (anchor edge x + top y), so the
   anchored edge never moves as lines change.
5. **Instrumental animation:** replace breathing dots in the pill (they read
   as "loading"). During instrumental breaks the pill contracts toward ball
   size and 2–3 small music-note glyphs rise out of it — drifting upward
   ~8-10pt while fading in/out, staggered on a ~2.2s loop, time-driven (not
   SwiftUI transitions). The popup's 3-line view may keep its existing
   indicator styles (settings picker unchanged).
6. **Pre-first-line / no-lyrics states** keep showing "♪ Title — Artist" in
   the pill (unchanged), at whatever width that text needs per rule 2.

## Design revision B (2026-07-25) — SUPERSEDES conflicting lines below

1. **Paused = dim only.** The breathing pulse is removed; a paused pill holds
   perfectly still at 60% opacity.
2. **Side parking.** The pill lives on the LEFT or RIGHT rail only
   (AssistiveTouch-style pick-and-drop): drag it anywhere, and on release it
   glides to the nearer rail at the drop height. Revision A's screen-third
   rule and center parking are gone (`.center` remains only for the first-run
   demo until the first drop; legacy persisted center anchors snap to the
   nearer rail at launch). Default placement: right rail, just below the
   menu bar.
3. **Smoother width transitions.** Near-critically-damped spring
   (0.45/0.92); the pill's offset is continuous anchor math sharing one
   spring with the width (no alignment flips), and no anchor spring runs
   while a drag is live.
4. **Pause robustness.** Pause events that arrive without a playback
   position must not clobber the frozen lyric position (the first-pause
   title-flash bug): while paused, an elapsed of ≈0 against a clock well
   past it is treated as missing data.

## Problem

"When I'm working I sometimes miss the lyrics of the song that's playing. I
want to read them clearly and instantly, right in front of my eyes, without
opening anything — and it must never interfere with what's on screen."

The notch-docked design solved this only for large notched Macs and fought
the menu bar for space. Verse 2.0 replaces it with a floating lyric pill.

## Product shape

One lyric engine, two visual states:

1. **Pill** — a slim floating capsule showing the current lyric line,
   always on top, draggable, clickable.
2. **Popup** — a translucent glass card the pill unfurls into on click:
   3-line karaoke, header, scrubber, transport.

The notch-docked mode is REMOVED (delete notch-specific geometry/rendering;
git history preserves it). No hover-expand anywhere — click is the trigger.

## The pill

**Geometry.** One line of text in a capsule, ~13pt lyric font, horizontal
padding ~16pt, height ~30pt. Max width ~min(38% of screen width, 460pt);
long lines use the existing chunking system (chunks sized to pill width,
crossfading pairs become single sequential chunks — no left/right split
anymore). Fixed width while a song plays (no per-line resizing); width may
differ per song/screen.

**Material.** Dark glass, not flat black: NSVisualEffectView
(.hudWindow-style material) with a low-opacity album-hue wash and a faint
1px inner border for definition. A soft outer glow in the album accent at
very low opacity. Text: bright tint from the album palette (existing
Palette pipeline).

**States.**
- *No music*: not on screen at all.
- *Song starts, before first lyric line*: pill shows "♪ Title — Artist"
  dimmed (replaces breathing dots as the pre-first-line state).
- *Singing*: current line with the active theme's animation (all four
  themes work in the pill; light wipe default).
- *Echo lines* (line text entirely inside (…) or […]): italic, ~75% size,
  ~55% brightness, soft fade in/out, no karaoke animation. Inline bracket
  spans mid-line: italic + dimmer, timing unchanged (word-based themes; ok
  to skip styling in single-Text themes if awkward).
- *Instrumental break* (>3s gap): pill contracts to a small capsule with
  three breathing dots. Break >15s: contract further to a tiny dot capsule
  (still visible — the user can always find it).
- *Paused*: wipe freezes mid-word, pill dims to ~60% with a slow ~3s
  breathing pulse. Visually distinct from stopped (gone) and playing.
- *No lyrics found*: pill shows "♪ Title — Artist" static; popup shows the
  empty state.

**Gestures.**
- *Drag*: move anywhere. Squash-and-stretch while dragging (slight scale on
  the drag axis), springy release. Snap guides: screen edge margins and
  horizontal center; remembers position (UserDefaults) per display
  arrangement. Clamped to visible frame (never under menu bar or dock —
  use NSScreen.visibleFrame).
- *Click*: expand to popup.
- *Double-click*: play/pause (with a small press-bounce animation).
  Single-click expand must be delayed just enough to disambiguate from
  double-click (~250ms) OR expand on mouse-up with double-click canceling
  the pending expand — pick whichever feels instant, but double-click must
  never open-then-close the popup.
- *Right-click*: context menu — Theme submenu (4 themes), Lyric timing
  (−0.5s/−0.1s/reset/+0.1s/+0.5s), "Hide until next song", Settings…, Quit.

## The popup

**Material.** True macOS vibrancy glass (blur of what's behind), washed
with the album hue at low opacity. NOT opaque black. Corner radius ~20pt.
Soft shadow.

**Anchoring.** Unfurls from the pill's position: pill anchors the popup's
top edge (popup grows downward) unless the pill is in the lower half of the
screen, then it grows upward. Clamped to visible frame. The pill's lyric
line morphs into the popup's current line (matchedGeometryEffect) — one
shared element, never a crossfade of two.

**Layout** (~380–420pt wide, content-driven height):
- Header: 36px album art (radius 9, click → open source player), display
  title cleaned of feat/remaster suffixes (share the cleaning regex with
  LyricsService.titleVariants — extract to one helper), artist muted below,
  album omitted, icon-only source glyph at right.
- Lyrics: exactly 3 lines (previous/current/next), serif, current line
  large with theme animation; neighbors small italic ~35% opacity. Click
  any line to seek (instant). Scroll → full-lyrics browse list, snaps back
  after 4s idle. Long current lines: fit-to-width font scaling (measure
  once per line, floor 60% of base size — never per-word ellipsis).
- Scrubber: 3px, thickens on hover, draggable, tabular timestamps.
- Transport row: prev / play-pause / next centered; settings glyph left;
  pin right (pin keeps popup open when clicking outside).
- Dismiss: click outside (unless pinned), Esc, or click the pill region
  again → exhale morph back into the pill.

## Animation charter (first-class requirement)

Everything spring-based, 120Hz ProMotion, no linear easing, nothing longer
than ~450ms. Respect the existing TimelineView lesson: crossfades driven by
playback time, not SwiftUI transitions, wherever content swaps per-frame.

1. *Appear*: song starts → pill inflates from a dot at its saved position
   (scale + width spring), text fades in ~120ms behind the shape.
2. *Wipe/theme animations*: as today, synced to vocal timing.
3. *Line change*: content springs (existing behavior carried over).
4. *Drag*: squash-stretch + magnetic snap on release.
5. *Click*: unfurl morph pill→popup (shared lyric element).
6. *Collapse*: popup exhales back into the pill.
7. *Instrumental*: width/scale contraction to dots capsule and back.
8. *Track change*: quick pulse as the palette shifts to the new album color
   (color animates, pill does one soft scale beat).
9. *Pause/resume*: dim + breathing / crisp return.
10. *Reduce Motion ON*: every spring becomes a ≤200ms fade; no scale
    choreography. (System accessibility setting.)

## Engineering carry-overs (already designed, keep)

- LRCLIB fetch: retries with backoff, title-variant cleaning, synced-first
  search fallback, disk cache. Cache hit must render with zero network wait.
- Sync: re-anchor playback clock every ~2s while playing (correct only
  drifts >0.3s), plus immediately on popup open. Poll must not run while
  idle and must not touch the main thread.
- Allowed sources: Spotify + Apple Music only.
- Timing offset slider (settings) + right-click nudge items write the same
  value.
- Four themes with the shared timing engine; word timings synthesized when
  LRCLIB has line-level only.

## Additional scope (agreed)

- First-run moment: on very first launch, the pill appears center-screen
  playing a built-in demo line loop with a one-time tooltip ("Drag me
  somewhere comfy — click to open"), settles wherever the user drops it.
- Battery/perf: TimelineView drivers fully stop when the pill is hidden or
  music is stopped; reduce animation frame work on battery where feasible.
- Peek hotkey (stretch, last): a global hotkey (default ⌥⇧L, changeable in
  settings) flashes the current line as a large centered HUD for ~2s.
  If it threatens the schedule, ship without it — it's the only optional
  item in this spec.

## Explicitly out / rejected

Notch-docked mode, hover-expand, volume/like/shuffle, lyric share cards,
screen-share auto-hide, BPM effects, fifth theme, karaoke fullscreen,
lyrics search, browser sources. Notarization is a user action (Apple
Developer account), not an implementation task.

## Technical architecture notes

- Keep the single borderless non-activating NSPanel approach; it must now
  accept clicks (pill is interactive). Keep PassThroughHostingView so only
  the pill/popup shape is hittable; the rest of the panel passes through.
- Panel frame strategy: size the panel to the popup's max footprint anchored
  at the pill position, or resize the panel between states — implementer's
  choice, but the morph must never visibly re-anchor.
- Drag: implement manually (mouseDown/mouseDragged on the pill region) so
  squash/snap animations can drive; persist position on mouseUp.
- Vibrancy: NSVisualEffectView under the SwiftUI hierarchy (behindWindow
  blending) with the album wash composited in SwiftUI on top.
- Esc/click-outside dismissal: local+global event monitors (existing scroll
  monitor shows the pattern).
- Settings window keeps: theme segmented control with live preview,
  instrumental style, timing slider, launch at login, (peek hotkey when
  built). Remove: hover-intent toggle.
- CLAUDE.md: rewrite the product description sections to match this spec
  (pill product; keep build order, LRCLIB, sources, restraint sections
  updated accordingly).

## Acceptance checklist

- [ ] Pill appears with inflate animation when Spotify starts a song; gone
      when music stops.
- [ ] Drag anywhere; position survives relaunch; never overlaps menu bar
      or dock.
- [ ] Click opens glass popup with morphing lyric; Esc/click-outside/pin
      behave as specced.
- [ ] Double-click toggles playback without opening the popup.
- [ ] Right-click menu: all items functional.
- [ ] Echo lines, instrumental contraction, paused dim, pre-first-line
      title all observable on a real song.
- [x] Long lines shrink-to-fit in popup; no per-word ellipsis anywhere.
- [ ] Same song replayed: lyrics render instantly (cache) and stay in sync
      through a manual seek in Spotify (re-anchor).
- [ ] Reduce Motion swaps springs for fades.
- [x] `./build.sh install` produces a working app; no compile warnings.

### Verification status (2026-07-24, implementation session)

Ticked boxes were verified deterministically: shrink-to-fit via the FittedFont
checks (floor/shrink behavior; the popup's current line calls the same
function at maxWidth 360, and the popup render path was exercised live without
crash) — neighbors use line-level tail truncation by design, never per-word;
build.sh install verified after every task (zero warnings, app running).

Unticked boxes could not be verified in this session and remain open for a
hands-on pass: the machine's screen capture was TCC-blocked (no pixels
observable) and Spotify stayed paused throughout (per instructions it was
never launched/unpaused, so no live playing states). Notes:
- Box 1 is SUPERSEDED by revision A: music stopping now contracts the pill to
  the idle ball; it is never "gone". The inflate is the ball→pill width spring.
- Box 2: anchor persistence + relaunch restore verified via UserDefaults
  round-trip (`verse.pillAnchor`), clamping check-verified; the drag gesture
  itself was not driven.
- Boxes 3–6: gesture/dismissal/menu wiring is in place (ExclusiveGesture,
  monitors) and all content-state logic (echo/instrumental/paused/pre-first-
  line) is check-verified; on-screen behavior unobserved.
- Box 8: clock re-anchoring was live-verified against playing Spotify during
  Task 3 (poll/correct/stop end-to-end); the lyrics disk cache predates 2.0.
  The replay-renders-instantly claim was not re-tested here.
- Box 9: the Motion.resolved mapping (springs → 0.18s fades under Reduce
  Motion) is check-verified; the live system toggle was not.
