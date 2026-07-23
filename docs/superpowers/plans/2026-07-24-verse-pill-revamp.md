# Verse 2.0 Floating Pill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the notch-docked UI with a draggable, clickable floating lyric pill that unfurls into a translucent glass karaoke popup, per `docs/superpowers/specs/2026-07-23-verse-pill-revamp-design.md` (read it first; it is the authority on every visual/behavioral value).

**Architecture:** One full-screen transparent non-activating NSPanel hosts a SwiftUI hierarchy. The pill is positioned by a model-owned origin point (drag moves the view, never the window). Popup anchors to the pill and morphs via matchedGeometryEffect. All content crossfades are playback-time-driven (SwiftUI transitions glitch inside TimelineView — see comment in CompactWingView.chunkView). Logic (title cleaning, echo detection, clock correction, font fitting, chunking) lives in plain testable types with a new XCTest target.

**Tech Stack:** Swift 5.9 SPM executable, SwiftUI + AppKit (NSPanel, NSVisualEffectView), XCTest. No new dependencies.

## Global Constraints

- macOS 14+, Swift 5.9, no external packages.
- Build/run loop: `swift build 2>&1 | tail -5` for compile checks; full verify = `pkill -x Verse; ./build.sh install && open /Applications/Verse.app && sleep 2 && pgrep -x Verse`.
- Tests: `swift test 2>&1 | tail -12` must pass before every commit.
- Zero compiler warnings in changed files.
- PRESERVE the user's renderer fixes from commit 42ada0a (wipe `mapped` gradient, `activeWordIndex` in-window guard, tracer `opacity(p > 0)`).
- Complex SwiftUI expressions can hit type-checker timeouts — hoist math into typed helper funcs (precedent: `BreathingDots` in VibeModeView.swift).
- Springs everywhere, nothing over ~450ms; every animation must have a Reduce Motion fallback (Task 9).
- Commit after every task: `git add -A && git commit -m "<type>: <what>"`. Never commit a failing build.

---

### Task 1: Test target + TitleCleaner extraction

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Verse/Lyrics/TitleCleaner.swift`
- Modify: `Sources/Verse/Lyrics/LyricsService.swift` (delete its `titleVariants`, call TitleCleaner)
- Create: `Tests/VerseTests/TitleCleanerTests.swift`

**Interfaces:**
- Produces: `enum TitleCleaner { static func clean(_ title: String) -> String; static func variants(_ title: String) -> [String] }`
  - `clean` strips `(feat./ft./featuring/with …)`, `[…]` equivalents, and ` - Remaster/Single Version/Radio Edit/Bonus Track/Deluxe/Mono/Stereo/Live…` suffixes (case-insensitive), trims; returns the input unchanged if cleaning empties it.
  - `variants` returns `[original]` or `[original, cleaned]` when they differ. LyricsService keeps identical fetch behavior via `TitleCleaner.variants`.

- [ ] **Step 1: Add test target to Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Verse",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Verse",
            path: "Sources/Verse"
        ),
        .testTarget(
            name: "VerseTests",
            dependencies: ["Verse"],
            path: "Tests/VerseTests"
        )
    ]
)
```

- [ ] **Step 2: Write failing tests**

`Tests/VerseTests/TitleCleanerTests.swift`:

```swift
import XCTest
@testable import Verse

final class TitleCleanerTests: XCTestCase {
    func testStripsFeatParenthetical() {
        XCTAssertEqual(TitleCleaner.clean("Like Him (feat. Lola Young)"), "Like Him")
        XCTAssertEqual(TitleCleaner.clean("Sicko Mode (with Drake)"), "Sicko Mode")
        XCTAssertEqual(TitleCleaner.clean("Stan [feat. Dido]"), "Stan")
    }
    func testStripsDashSuffixes() {
        XCTAssertEqual(TitleCleaner.clean("Come Together - Remastered 2009"), "Come Together")
        XCTAssertEqual(TitleCleaner.clean("Let It Be - Single Version"), "Let It Be")
    }
    func testLeavesCleanTitlesAlone() {
        XCTAssertEqual(TitleCleaner.clean("WITHOUT ME"), "WITHOUT ME")
        XCTAssertEqual(TitleCleaner.clean("Plain Song"), "Plain Song")
    }
    func testVariants() {
        XCTAssertEqual(TitleCleaner.variants("Plain Song"), ["Plain Song"])
        XCTAssertEqual(TitleCleaner.variants("Like Him (feat. Lola Young)"),
                       ["Like Him (feat. Lola Young)", "Like Him"])
    }
}
```

- [ ] **Step 3: Run `swift test` — expect FAIL (TitleCleaner undefined)**
- [ ] **Step 4: Implement `TitleCleaner` by MOVING the two regex passes verbatim from `LyricsService.titleVariants` into `clean`, with `variants` composing it. Update `LyricsService.fetchRecord` to call `TitleCleaner.variants(state.title)` and delete the old static.** Internal-access types are visible to `@testable import` — no access-level changes needed.
- [ ] **Step 5: `swift test` → all pass; `swift build` clean.**
- [ ] **Step 6: Commit** `git add -A && git commit -m "refactor: extract TitleCleaner with tests"`

---

### Task 2: Echo detection (bracket lyrics)

**Files:**
- Modify: `Sources/Verse/Lyrics/LyricModels.swift`
- Modify: `Sources/Verse/Lyrics/LRCParser.swift`
- Create: `Tests/VerseTests/EchoDetectionTests.swift`

**Interfaces:**
- Produces: `LyricLine.isEcho: Bool` (stored, default false) — true when the trimmed line text is entirely wrapped by `(…)` or `[…]`.
- Produces: `WordTiming.isEcho: Bool` (stored, default false) — true for words inside a bracketed span (inline ad-libs). Both flags flow through `LyricsTimeline.synthesizeWords` (parse bracket depth while tokenizing) and `LRCParser`.
- `LyricChunk` word arrays inherit the flags automatically (they slice `line.words`).

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import Verse

final class EchoDetectionTests: XCTestCase {
    func testWholeLineEcho() {
        let t = LRCParser.parse("[00:10.00](ooh, la la)\n[00:14.00]Real line here")!
        XCTAssertTrue(t.lines[0].isEcho)
        XCTAssertFalse(t.lines[1].isEcho)
    }
    func testSquareBracketEcho() {
        let t = LRCParser.parse("[00:10.00][background hum]\n[00:12.00]Words")!
        XCTAssertTrue(t.lines[0].isEcho)
    }
    func testInlineEchoWords() {
        let words = LyricsTimeline.synthesizeWords(text: "run away (ooh) tonight", start: 0, end: 4)
        XCTAssertEqual(words.map(\.isEcho), [false, false, true, false])
    }
    func testNoBracketsNoEcho() {
        let words = LyricsTimeline.synthesizeWords(text: "plain words only", start: 0, end: 2)
        XCTAssertTrue(words.allSatisfy { !$0.isEcho })
    }
}
```

- [ ] **Step 2: `swift test` → FAIL (no `isEcho`).**
- [ ] **Step 3: Implement.** `WordTiming` gains `var isEcho: Bool = false` (update memberwise call sites — default keeps most compiling). `LyricLine` gains `var isEcho: Bool = false`. In `synthesizeWords`, track paren/bracket depth per token: a token beginning with `(`/`[` raises depth before flagging, ending with `)`/`]` lowers after; token isEcho when depth > 0 at its position. In `LRCParser.parse`, whole-line check on `plainText`: `text.hasPrefix("(") && text.hasSuffix(")")` or `[`/`]`, with no closing bracket before the final character (`text.dropLast().filter { $0 == ")" }.isEmpty` style guard for the simple v1 rule); set `isEcho` on the built `LyricLine`. Careful: `parseEnhancedWords` path also sets word flags via the same depth tracker (extract `static func markEcho(_ tokens: [String]) -> [Bool]` used by both).
- [ ] **Step 4: `swift test` → pass; build clean. Commit** `feat: echo detection for bracketed lyrics`

---

### Task 3: Clock correction + position re-anchor poller

**Files:**
- Modify: `Sources/Verse/NowPlaying/NowPlayingState.swift` (PlaybackClock)
- Create: `Sources/Verse/NowPlaying/PositionPoller.swift`
- Modify: `Sources/Verse/NowPlaying/NowPlayingCoordinator.swift`
- Create: `Tests/VerseTests/PlaybackClockTests.swift`

**Interfaces:**
- Produces: `PlaybackClock.correct(to elapsed: TimeInterval, tolerance: TimeInterval = 0.3) -> Bool` — returns true and re-bases only when `|position() − elapsed| > tolerance`; otherwise no-op returning false.
- Produces: `final class PositionPoller` — `init(interval: TimeInterval = 2.0)`, `var onPosition: ((TimeInterval) -> Void)?`, `func start(bundleID: String)`, `func stop()`, `func pollOnce(bundleID: String)`. Runs `osascript -e 'tell application id "BUNDLE" to player position'` (works for Spotify AND Apple Music, both scriptable) on a background DispatchQueue timer; parses Double from stdout; never touches the main thread; `stop()` cancels the timer. Must self-stop if the osascript exits nonzero 3 times in a row (app quit).
- Coordinator: starts the poller when a state update says `isPlaying == true` (allowed source), stops on pause/stop/nil; on `onPosition` calls `clock.correct(to:)`. Exposes `func resyncNow()` (calls `pollOnce`) for popup-open. AppModel gets `func resyncNow()` passthrough.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import Verse

final class PlaybackClockTests: XCTestCase {
    func testCorrectIgnoresSmallDrift() {
        let clock = PlaybackClock()
        clock.update(elapsed: 10, playing: true, rate: 1, duration: 100)
        XCTAssertFalse(clock.correct(to: clock.position() + 0.1))
    }
    func testCorrectAppliesLargeDrift() {
        let clock = PlaybackClock()
        clock.update(elapsed: 10, playing: true, rate: 1, duration: 100)
        XCTAssertTrue(clock.correct(to: clock.position() + 2.0))
        XCTAssertEqual(clock.position(), 12, accuracy: 0.3)
    }
    func testCorrectRespectsCustomTolerance() {
        let clock = PlaybackClock()
        clock.update(elapsed: 5, playing: false, rate: 1, duration: 100)
        XCTAssertFalse(clock.correct(to: 5.4, tolerance: 0.5))
        XCTAssertTrue(clock.correct(to: 6.1, tolerance: 0.5))
    }
}
```

- [ ] **Step 2: FAIL → implement `correct` (lock-guarded, re-base `baseElapsed`/`baseUptime` like `jump`).**
- [ ] **Step 3: Implement PositionPoller with `DispatchSourceTimer` on `DispatchQueue(label: "verse.poller", qos: .utility)`; Process + Pipe for osascript; wire into coordinator per the interface block (poller lives in the coordinator; remember the current allowed bundleID from the last state).**
- [ ] **Step 4: `swift test` pass; build; manual check: play Spotify, seek in the Spotify app, lyric follows within ~2s. Commit** `feat: playback clock re-anchoring via position poller`

---

### Task 4: Fitted font helper

**Files:**
- Create: `Sources/Verse/UI/FittedFont.swift`
- Create: `Tests/VerseTests/FittedFontTests.swift`

**Interfaces:**
- Produces: `enum FittedFont { static func pointSize(text: String, base: CGFloat, weight: NSFont.Weight, design: NSFontDescriptor.SystemDesign, maxWidth: CGFloat, floorFactor: CGFloat = 0.6) -> CGFloat }`
  - Measures the text width at `base` via `NSFont` + `size(withAttributes:)` (serif design resolved via `NSFont.systemFont(ofSize:weight:).fontDescriptor.withDesign(design)`), returns `base * clamp(maxWidth/naturalWidth, floorFactor, 1.0)`.
  - Caches results in a `private static let cache = NSCache<NSString, NSNumber>()` keyed `"\(text)|\(base)|\(maxWidth)|\(weight.rawValue)"` — callers may invoke per frame.

- [ ] **Step 1: Failing tests** (short text returns base; long text shrinks monotonically; floor respected):

```swift
import XCTest
@testable import Verse

final class FittedFontTests: XCTestCase {
    func testShortTextKeepsBaseSize() {
        XCTAssertEqual(FittedFont.pointSize(text: "Hi", base: 21, weight: .semibold,
                                            design: .serif, maxWidth: 400), 21)
    }
    func testLongTextShrinks() {
        let long = String(repeating: "supercalifragilistic ", count: 6)
        let s = FittedFont.pointSize(text: long, base: 21, weight: .semibold,
                                     design: .serif, maxWidth: 400)
        XCTAssertLessThan(s, 21)
        XCTAssertGreaterThanOrEqual(s, 21 * 0.6)
    }
    func testFloorHolds() {
        let absurd = String(repeating: "wordswordswords ", count: 60)
        let s = FittedFont.pointSize(text: absurd, base: 20, weight: .semibold,
                                     design: .serif, maxWidth: 300, floorFactor: 0.6)
        XCTAssertEqual(s, 12, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: FAIL → implement → pass → commit** `feat: per-line fitted font sizing`

---

### Task 5: Pill window layer (panel, layout, drag persistence)

**Files:**
- Create: `Sources/Verse/UI/PillPanelController.swift`
- Create: `Sources/Verse/UI/PillLayout.swift`
- Modify: `Sources/Verse/AppModel.swift`
- Modify: `Sources/Verse/VerseApp.swift`

**Interfaces:**
- Produces: `enum PillUIState { case hidden, pill, popup }` (in AppModel.swift, REPLACING `NotchUIState`; AppModel property stays named `uiState`).
- Produces: `struct PillLayout` — `pillHeight: CGFloat = 30`, `pillMaxWidth(screen: NSScreen) -> CGFloat` (= `min(screen.frame.width * 0.38, 460)`), `popupSize = CGSize(width: 400, height: 248)`, `edgeMargin: CGFloat = 12`.
- Produces: AppModel additions: `@Published var pillOrigin: CGPoint` (top-left of pill in panel/screen coords, persisted to UserDefaults key `"verse.pillOrigin"` as `"x,y"` on change, default = top-center: `((screenW − pillW)/2, visibleFrame.maxY − 8 − pillHeight)` computed at first launch), `@Published var pillWidth: CGFloat`, `func clampPillOrigin(to visible: CGRect)`.
- Produces: `PillPanelController` — full-screen transparent NSPanel (frame = `screen.frame`), `.borderless + .nonactivatingPanel`, level statusBar+1, `collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, `hasShadow = false` (shadows drawn in SwiftUI), hosts `RootPillView` in the existing `PassThroughHostingView` with `interactiveRect` = pill rect when `.pill`, popup rect ∪ pill rect when `.popup`, `.zero` when hidden. Repositions on `didChangeScreenParametersNotification`. DELETE nothing yet — old notch files still compile alongside (VerseApp switches to PillPanelController; NotchPanelController becomes unreferenced).
- `VerseApp` constructs `PillPanelController` instead of `NotchPanelController` (status item stays; drop the `statusItemMinX` plumbing).
- Temporary `RootPillView` stub for this task: a `RoundedRectangle` dark-gray capsule at `pillOrigin` sized `pillWidth × 30`, draggable via `DragGesture` updating `model.pillOrigin` (clamped to `visibleFrame` minus `edgeMargin`), no content. This proves window, hit-testing, drag, persistence, clamping before any real UI.

- [ ] **Step 1: Implement PillLayout + AppModel state/origin changes (persist in `didSet`, parse on init; replace all `NotchUIState` references — `.compact` → `.pill`, `.expanded` → `.popup` across AppModel/StatusItem/Settings; RootNotchView/VibeMode/CompactWing keep compiling by switching their references too, they'll be deleted in Task 8).**
- [ ] **Step 2: Implement PillPanelController + stub RootPillView; wire VerseApp.**
- [ ] **Step 3: Build + install + run. Verify: gray capsule appears when music plays (uiState pill on play — reuse existing apply() logic), drags smoothly, cannot cross menu bar/dock (clamp uses `NSScreen.visibleFrame`), position survives relaunch, clicks elsewhere on screen pass through to other apps.**
- [ ] **Step 4: Commit** `feat: pill window layer with drag + persistence`

---

### Task 6: Pill content + states

**Files:**
- Create: `Sources/Verse/UI/PillView.swift`
- Create: `Sources/Verse/UI/GlassBackground.swift`
- Modify: `Sources/Verse/UI/RootPillView` stub (in PillPanelController.swift or its own file — move to `Sources/Verse/UI/RootPillView.swift`)
- Modify: `Sources/Verse/AppModel.swift` (chunk width = pill text width)

**Interfaces:**
- Produces: `struct GlassBackground: NSViewRepresentable` — NSVisualEffectView, `material: .hudWindow`, `blendingMode: .behindWindow`, `state: .active`, wrapped by callers in any clip shape.
- Produces: `struct PillView: View` (`model`, `morph: Namespace.ID`, `t` supplied by RootPillView's TimelineView). Renders per spec "The pill / States":
  - Capsule: GlassBackground + `model.palette.background.opacity(0.35)` wash + `Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1)` + outer shadow `model.palette.accent.opacity(0.25), radius 12`.
  - Content by state, all crossfades time-driven (reuse the `pairFade` pattern as `chunkFade`): pre-first-line & plain & none → `"♪ Title — Artist"` dimmed static; synced → active chunk via `LyricLineRenderer` (chunks now sized to `pillWidth − 32`, sequential single chunks — delete pair logic); echo chunk (`chunk.words.allSatisfy(\.isEcho)` or backing line flag via `lineIndex` lookup) → italic serif at 75% of 13pt, 55% brightness, no theme animation (plain Text with time-fade); instrumental gap >3s → `BreathingDots` (move struct out of VibeModeView into PillView.swift unchanged); gap >15s → dots capsule shrinks to `width: 56` (animate width on the capsule frame).
  - Paused (`model.now?.isPlaying == false` while song present): freeze `t` at pause moment (AppModel captures `pausedAt` when isPlaying flips false; `lyricPosition()` returns the frozen value while paused), pill `.opacity(0.6)` with 3s breathing `scaleEffect` (time-driven sine, amplitude 0.015).
  - Lyric text uses `.matchedGeometryEffect(id: "currentLyric", in: morph, isSource: model.uiState != .popup)` on its container.
- AppModel: `wingTextWidth` renamed `pillTextWidth`; chunking call uses `pillWidth − 32`; `LyricChunker` untouched.

- [ ] **Step 1: Implement GlassBackground + PillView + RootPillView integration (TimelineView(.animation) drives `t = model.lyricPosition()`; pill positioned via `.offset(x: pillOrigin.x, y: screenTopInset…)` inside a top-leading aligned full-panel ZStack).**
- [ ] **Step 2: Rename wingTextWidth → pillTextWidth everywhere; delete CompactWingView's pair logic dependency by leaving that file uncompiled? NO — files must keep compiling until deletion (Task 8); leave CompactWingView untouched and unreferenced instead.**
- [ ] **Step 3: Build + install + run with Spotify: verify every pill state from the spec's States list by playing (a) a normal synced song, (b) a song with `(…)` ad-lib lines, (c) pausing mid-word (wipe freezes, pill dims/breathes), (d) a track with a long intro (title shows pre-first-line), (e) an instrumental gap (dots, then shrink if >15s).**
- [ ] **Step 4: Commit** `feat: pill content states with glass material`

---

### Task 7: Appear/disappear + gesture grammar

**Files:**
- Modify: `Sources/Verse/UI/RootPillView.swift`
- Modify: `Sources/Verse/AppModel.swift`

**Interfaces:**
- Produces: AppModel `@Published var hiddenUntilTrackChange: Bool = false` (reset to false inside `apply()` when `trackChanged`); when true, uiState forced `.hidden` while the song continues.
- Gestures on the pill (exact composition to avoid open-then-close):
```swift
.gesture(
    ExclusiveGesture(
        TapGesture(count: 2).onEnded { model.togglePlayPause(); bounce() },
        TapGesture(count: 1).onEnded { expand() }
    )
)
.simultaneousGesture(dragGesture)   // drag from Task 5, threshold 3pt so taps don't jitter
.contextMenu { PillContextMenu(model: model) }
```
- `PillContextMenu`: Theme submenu (4 themes, checkmark on current), "Lyric timing" submenu (−0.5s, −0.1s, Reset, +0.1s, +0.5s adjusting `model.syncOffset`), Divider, "Hide until next song" (`hiddenUntilTrackChange = true`), Divider, "Settings…" (`model.openSettings?()`), "Quit Verse" (`NSApp.terminate`).
- Appear/disappear: hidden→pill inflates from a dot — pill rendered with `scaleEffect(appearProgress)` + width from `8 → pillWidth`, spring `(response 0.45, damping 0.8)`, text opacity ramps over the final 0.15 of the progress; driven by a model-published `Bool` animated with `withAnimation` at state change (this is a state-change animation, not a per-frame one — SwiftUI springs are correct here, unlike content crossfades). pill→hidden reverses. Double-click bounce: quick `scaleEffect` 1 → 0.94 → 1 spring.

- [ ] **Step 1: Implement gestures + context menu + hide-until-next-song.**
- [ ] **Step 2: Implement inflate/deflate; verify with music start/stop, and `hiddenUntilTrackChange` (pill vanishes, returns on next track).**
- [ ] **Step 3: Verify double-click toggles playback WITHOUT the popup ever flashing open; single click currently calls `expand()` which can just set `uiState = .popup` (popup itself is Task 8 — a placeholder gray card is fine this task).**
- [ ] **Step 4: Build/install/run all gestures; commit** `feat: pill gesture grammar and appear animation`

---

### Task 8: Glass popup + morph + dismissal (+ delete notch code)

**Files:**
- Create: `Sources/Verse/UI/PopupView.swift` (start from VibeModeView's lyrics/scrubber/controls internals — copy, then adapt)
- Modify: `Sources/Verse/UI/RootPillView.swift`
- Modify: `Sources/Verse/UI/PillPanelController.swift` (interactiveRect for popup; event monitors)
- Delete: `Sources/Verse/UI/RootNotchView.swift`, `Sources/Verse/UI/CompactWingView.swift`, `Sources/Verse/UI/VibeModeView.swift`, `Sources/Verse/UI/NotchPanelController.swift`
- Modify: `Sources/Verse/Settings/SettingsView.swift` (drop hover-intent toggle; keep ThemePreview — move `LyricRenderStyle` deps as needed)
- Modify: `Sources/Verse/AppModel.swift` (drop `hoverIntentDelay`; popup-open hook calls `resyncNow()`)

**Interfaces:**
- Produces: `struct PopupView: View` per spec "The popup": 400×248 glass card (GlassBackground + palette wash 0.25 + radius 20 + shadow), header (36px art button → `openSourcePlayer()`, `TitleCleaner.clean(title)` 13.5 semibold bright, artist 11 muted, `music.note` glyph capsule right), 3-line karaoke (carry VibeModeView's threeLines/browse/scrubber/controls code including click-to-seek, scroll-browse via the existing scroll monitor, pin), current line font via `FittedFont.pointSize(text:, base: 21.5, …, maxWidth: 400 − 40)`, echo current line = italic 75%/55% no animation, neighbors italic tail-truncated.
- Popup placement: computed in RootPillView — anchored to pill: grows downward from pill top if `pillOrigin.y` is in the top half of `visibleFrame`, else upward from pill bottom; horizontal center on the pill center clamped to `visibleFrame + edgeMargin`. Pill's lyric container is the matchedGeometry source when `.pill`; PopupView's current-line container is source when `.popup` (same id "currentLyric" — the morph carries the line between them).
- Dismissal (PillPanelController): local monitor for `keyDown` Esc → collapse; local+global monitors for `leftMouseDown`/`rightMouseDown` outside the popup rect → collapse unless `model.pinned`. Collapse = `uiState = .pill` with the exhale spring. Opening the popup calls `model.resyncNow()`.

- [ ] **Step 1: Build PopupView (copy VibeModeView internals, adapt to glass + fitted font + clean title + echo styling; keep the 42ada0a "continuous sliding" line behavior intact when porting threeLines).**
- [ ] **Step 2: Wire morph + placement + flip; then dismissal monitors + pin + Esc + resync-on-open.**
- [ ] **Step 3: Delete the four notch files; fix all remaining references (`NotchLayout`, `NotchShape`, `interactiveRect` compact case, StatusItemController's `buttonScreenMinX` if now unused). `swift build` must be clean with zero warnings.**
- [ ] **Step 4: `swift test` still green. Full run: click pill → glass card unfurls with the lyric morphing; Esc / outside-click / pin / re-click behaviors; click-line-to-seek instant; scrubber drag; scroll-browse snapback.**
- [ ] **Step 5: Commit** `feat: glass popup with morph; remove notch mode`

---

### Task 9: Reduce Motion + battery/perf + first-run

**Files:**
- Create: `Sources/Verse/UI/Motion.swift`
- Modify: `Sources/Verse/AppModel.swift`, `Sources/Verse/UI/RootPillView.swift`, `Sources/Verse/UI/PillView.swift`, `Sources/Verse/UI/PopupView.swift`, `Sources/Verse/VerseApp.swift`

**Interfaces:**
- Produces: `enum Motion { @MainActor static var reduce: Bool; static func spring(_ response: Double, _ damping: Double) -> Animation }` — returns `.easeOut(duration: 0.18)` when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`; AppModel observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` and republishes so views refresh. EVERY `withAnimation`/`.animation` call in pill/popup goes through `Motion.spring`; time-driven choreography (inflate progress, squash) collapses to opacity fades when `Motion.reduce`.
- Battery/perf: RootPillView's `TimelineView` uses `.animation(minimumInterval: model.frameInterval)` where AppModel computes `frameInterval: Double?` — `nil` (uncapped) normally, `1.0/30.0` when `ProcessInfo.processInfo.isLowPowerModeEnabled` (observe `NSProcessInfo.powerStateDidChangeNotification`). When `uiState == .hidden` RootPillView renders `EmptyView` (no TimelineView mounted at all). PositionPoller already stops when not playing (Task 3) — verify.
- First-run: AppModel `isFirstRun` (UserDefaults `"verse.launched"` absent). While first-run AND no music playing, show the pill center-screen with a built-in demo loop: text "and the city hums along in gold", synthesized words over a 4.5s loop (reuse `ThemePreview`'s loop pattern), plus a one-time caption below the pill: "Drag me somewhere comfy — click to open" (11pt, 60% white, fades after 8s). First real track OR first drag ends the demo permanently (`set "verse.launched"`).

- [ ] **Step 1: Motion helper + sweep every animation call.** Toggle System Settings → Accessibility → Display → Reduce Motion and verify springs become fades.
- [ ] **Step 2: frameInterval plumbing + hidden = unmounted; verify CPU near zero when idle (Activity Monitor).**
- [ ] **Step 3: First-run demo (delete the `verse.launched` default to test: `defaults delete dev.rohan.verse verse.launched`).**
- [ ] **Step 4: Tests green; build/install/run; commit** `feat: reduce motion, battery awareness, first-run moment`

---

### Task 10: CLAUDE.md rewrite + acceptance sweep

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-07-23-verse-pill-revamp-design.md` (tick acceptance boxes)

- [ ] **Step 1: Rewrite CLAUDE.md's product sections** — replace the two-state notch description, compact/expanded sections, notch geometry/build-order bullets with the pill product: summary (pill + glass popup), pointer to the spec file as design authority, keep LRCLIB/sources/color/animation-engineering/restraint sections (updating "no hover" and removing notch references). Keep build.sh instructions.
- [ ] **Step 2: Run the spec's acceptance checklist top to bottom against the installed app with real Spotify playback; tick each `- [ ]` in the spec that passes; FIX anything that fails before ticking (small fixes inline; anything structural → report).**
- [ ] **Step 3: `swift test` + zero-warning build. Commit** `docs: pill-era CLAUDE.md; acceptance checklist pass`

---

### Task 11 (STRETCH — skip if anything above slipped): Peek hotkey

**Files:**
- Create: `Sources/Verse/Peek/HotKeyCenter.swift`, `Sources/Verse/Peek/PeekHUDController.swift`
- Modify: `Sources/Verse/AppModel.swift`, `Sources/Verse/Settings/SettingsView.swift`

**Interfaces:**
- `HotKeyCenter`: Carbon `RegisterEventHotKey` wrapper — `register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void)`, `unregister()`. Default ⌥⇧L (`kVK_ANSI_L`, `optionKey|shiftKey`).
- `PeekHUDController`: borderless non-activating panel, center of active screen, shows the current line (or "♪ Title — Artist") in 28pt serif on a glass card, fades in 150ms, holds 2s, fades out; repeated triggers restart the timer.
- Settings: toggle "Peek hotkey (⌥⇧L)" on/off (no recorder UI — fixed combo v1).

- [ ] Implement, verify with music playing and stopped, commit `feat: peek hotkey HUD (stretch)`

---

## Self-Review Notes (done)

- Spec coverage: every spec section maps to a task (pill states→6, gestures→7, popup→8, charter items 1–9→6/7/8, item 10→9, carry-overs→1/3/4 + preserved code, polish 1–7→6/7/9, hotkey→11, CLAUDE.md + checklist→10). Glass material, echo, paused-freeze, pre-first-line, dots contraction all placed.
- Type consistency: `PillUIState.{hidden,pill,popup}`, `pillTextWidth`, `TitleCleaner`, `Motion.spring`, `FittedFont.pointSize`, `chunkFade` used consistently across tasks.
- The `lyricPosition()` pause-freeze (Task 6) must land before Task 9's frame gating — order holds.
