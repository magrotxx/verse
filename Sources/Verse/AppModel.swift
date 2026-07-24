import AppKit
import SwiftUI
import Combine

enum LyricTheme: String, CaseIterable, Identifiable {
    case lightWipe = "lightWipe"    // default
    case typeOn = "typeOn"          // most expressive
    case spotlight = "spotlight"
    case tracer = "tracer"          // most minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lightWipe: return "Light wipe"
        case .typeOn: return "Type-on"
        case .spotlight: return "Spotlight"
        case .tracer: return "Tracer"
        }
    }
}

enum InstrumentalStyle: String, CaseIterable, Identifiable {
    case breathingDots, countdown, bigArt
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .breathingDots: return "Breathing dots"
        case .countdown: return "Countdown"
        case .bigArt: return "Album art"
        }
    }
}

/// The pill's three visual states (renamed from the old notch `NotchUIState`;
/// `.compact` → `.pill`, `.expanded` → `.popup`).
enum PillUIState { case hidden, pill, popup }

@MainActor
final class AppModel: ObservableObject {
    // MARK: - Published state
    @Published private(set) var now: NowPlayingState?
    @Published private(set) var content: LyricsContent = .none
    @Published private(set) var compactChunks: [LyricChunk] = []
    @Published private(set) var palette: Palette = .fallback
    @Published var uiState: PillUIState = .hidden
    @Published var pinned = false
    @Published var browsing = false          // scroll-to-browse full list in vibe mode
    @Published var scrubbing = false

    // MARK: - Settings (persisted)
    @Published var theme: LyricTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "verse.theme") }
    }
    @Published var hoverIntentDelay: Bool {  // 150ms hover-intent before expanding
        didSet { UserDefaults.standard.set(hoverIntentDelay, forKey: "verse.hoverIntent") }
    }
    @Published var instrumentalStyle: InstrumentalStyle {
        didSet { UserDefaults.standard.set(instrumentalStyle.rawValue, forKey: "verse.instrumental") }
    }
    /// Seconds added to the playback position for lyric timing only (scrubber
    /// shows the true position). Positive → lyrics appear earlier; compensates
    /// for Bluetooth latency and imperfect community timestamps.
    @Published var syncOffset: Double {
        didSet { UserDefaults.standard.set(syncOffset, forKey: "verse.syncOffset") }
    }

    // MARK: - Geometry (set by the panel controller at launch / on screen change)
    /// Font used to MEASURE chunks — must match the pill's lyric render size
    /// (`LyricRenderStyle.pill`, 13pt medium) or chunks would over/underflow.
    let pillFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    /// Text budget for chunking: the pill width minus 16pt of horizontal padding
    /// on each side. Chunks are sized to fit this so the fixed-width pill never
    /// resizes per line.
    var pillTextWidth: CGFloat { pillWidth - 32 }

    /// Pure geometry helpers (pill/popup size, clamping, coordinate flips).
    let pillLayout = PillLayout()

    /// The pill's TOP-LEFT corner in SwiftUI panel space (top-left origin,
    /// Y grows down). Persisted so the pill returns to where the user dropped
    /// it. See `PillLayout` for the space definitions.
    @Published var pillOrigin: CGPoint {
        didSet {
            hasStoredPillOrigin = true
            UserDefaults.standard.set("\(pillOrigin.x),\(pillOrigin.y)", forKey: "verse.pillOrigin")
        }
    }

    /// Fixed capsule width while a song plays (no per-line resizing). Set by the
    /// panel controller from the screen; chunks fit within `pillTextWidth`.
    @Published var pillWidth: CGFloat = 240

    /// The current screen's visible area (excludes menu bar + dock) expressed in
    /// panel space. Written by the panel controller; read for live drag-clamping
    /// and popup placement. Not `@Published` — every mutation of `pillOrigin`
    /// that depends on it is applied imperatively right after it changes.
    var pillVisibleRect: CGRect = .zero

    /// False until the very first launch persists a position; lets the panel
    /// controller drop the pill at its default spot only once.
    private(set) var hasStoredPillOrigin = false

    // MARK: - Engine
    let clock = PlaybackClock()
    private lazy var coordinator = NowPlayingCoordinator(clock: clock)
    private let lyricsService = LyricsService()
    private let paletteCache = PaletteCache()
    private var lyricsTask: Task<Void, Never>?
    private var currentTrackKey: String?
    private var browseTimer: Timer?

    /// Lyric time frozen at the moment playback paused, so the wipe/spotlight
    /// stops mid-word instead of drifting on the interpolating clock. `nil`
    /// while playing. See `lyricPosition()`.
    private var pausedLyricPosition: TimeInterval?

    var openSettings: (@MainActor () -> Void)?

    init() {
        let defaults = UserDefaults.standard
        theme = LyricTheme(rawValue: defaults.string(forKey: "verse.theme") ?? "") ?? .lightWipe
        hoverIntentDelay = defaults.object(forKey: "verse.hoverIntent") as? Bool ?? true
        instrumentalStyle = InstrumentalStyle(
            rawValue: defaults.string(forKey: "verse.instrumental") ?? "") ?? .breathingDots
        syncOffset = defaults.double(forKey: "verse.syncOffset")

        // Restore the pill's saved position ("x,y"). didSet does NOT fire for
        // these initial assignments, so `hasStoredPillOrigin` is set by hand —
        // the panel controller uses it to place the pill at its default spot
        // only when nothing was persisted yet.
        if let saved = defaults.string(forKey: "verse.pillOrigin") {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                pillOrigin = CGPoint(x: parts[0], y: parts[1])
                hasStoredPillOrigin = true
            } else {
                pillOrigin = .zero
            }
        } else {
            pillOrigin = .zero
        }
    }

    /// Clamp `pillOrigin` so the whole pill stays inside `visible` (panel space)
    /// with the layout's edge margin. Assigning `pillOrigin` persists it.
    func clampPillOrigin(to visible: CGRect) {
        pillOrigin = pillLayout.clampedOrigin(pillOrigin, pillWidth: pillWidth, visible: visible)
    }

    // MARK: - Lifecycle

    func start() {
        coordinator.onUpdate = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
        coordinator.start()
        observeFullscreen()
    }

    func stop() {
        coordinator.stop()
        lyricsTask?.cancel()
    }

    private func apply(_ state: NowPlayingState?) {
        guard let state else {
            now = nil
            currentTrackKey = nil
            content = .none
            compactChunks = []
            pausedLyricPosition = nil
            if uiState != .hidden { uiState = .hidden }
            return
        }

        let trackChanged = state.trackKey != currentTrackKey
        let artworkArrived = now?.artwork == nil && state.artwork != nil
        now = state
        if uiState == .hidden { uiState = .pill }

        // Freeze lyric time on pause (capture once), release on resume. Capturing
        // here — after the coordinator has pushed the paused position into the
        // clock — pins the wipe to exactly where the vocal stopped.
        if state.isPlaying {
            pausedLyricPosition = nil
        } else if pausedLyricPosition == nil {
            pausedLyricPosition = clock.position()
        }

        if trackChanged {
            currentTrackKey = state.trackKey
            content = .none
            compactChunks = []
            fetchLyrics(for: state)
        }
        if trackChanged || artworkArrived {
            palette = paletteCache.palette(
                for: "\(state.artist)|\(state.album)",
                artwork: state.artwork
            )
        }
    }

    private func fetchLyrics(for state: NowPlayingState) {
        lyricsTask?.cancel()
        let key = state.trackKey
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.lyricsService.lyrics(for: state)
            guard !Task.isCancelled, self.currentTrackKey == key else { return }
            self.content = result
            if case .synced(let timeline) = result {
                self.compactChunks = LyricChunker.chunks(
                    for: timeline,
                    maxWidth: self.pillTextWidth,
                    font: self.pillFont
                )
            } else {
                self.compactChunks = []
            }
        }
    }

    // MARK: - Derived

    var timeline: LyricsTimeline? {
        if case .synced(let t) = content { return t }
        return nil
    }

    func position() -> TimeInterval { clock.position() }

    /// Playback position shifted by the user's lyric-timing offset — use this
    /// for anything lyric-synced; use `position()` for the scrubber. Returns the
    /// frozen pause position while paused so the theme animation holds mid-word.
    func lyricPosition() -> TimeInterval { (pausedLyricPosition ?? clock.position()) + syncOffset }

    /// True when a song is loaded but paused (distinct from stopped/`nil`).
    var isPaused: Bool { now != nil && now?.isPlaying == false }

    // MARK: - Transport

    func togglePlayPause() { coordinator.togglePlayPause() }
    func nextTrack() { coordinator.nextTrack() }
    func previousTrack() { coordinator.previousTrack() }

    func seek(to seconds: TimeInterval) {
        guard let duration = now?.duration, duration > 0 else { return }
        let clamped = min(max(seconds, 0), duration)
        coordinator.seek(to: clamped)
        // Seeking while paused must move the frozen lyric with the scrubber.
        if pausedLyricPosition != nil { pausedLyricPosition = clamped }
    }

    /// Re-anchor the playback clock against ground truth right now, instead
    /// of waiting for the next scheduled poll. Intended to be called when
    /// the popup opens.
    func resyncNow() { coordinator.resyncNow() }

    func openSourcePlayer() {
        guard let id = now?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: - Browse mode (scroll inside the panel → full lyrics list)

    func enterBrowse() {
        guard uiState == .popup, timeline != nil else { return }
        browsing = true
        restartBrowseTimer()
    }

    func restartBrowseTimer() {
        browseTimer?.invalidate()
        browseTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.browsing = false }
        }
    }

    func exitBrowse() {
        browseTimer?.invalidate()
        browsing = false
    }

    // MARK: - Pinned auto-collapse when a fullscreen app/video starts

    private func observeFullscreen() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pinned else { return }
                if Self.frontmostSpaceIsFullscreen() {
                    self.pinned = false
                    self.uiState = self.now == nil ? .hidden : .pill
                    self.exitBrowse()
                }
            }
        }
    }

    private static func frontmostSpaceIsFullscreen() -> Bool {
        guard let screen = NSScreen.main,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]]
        else { return false }
        let screenFrame = screen.frame
        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"]
            else { continue }
            // A layer-0 window covering the full screen (incl. menu bar area)
            // means a fullscreen space is frontmost.
            if w >= screenFrame.width && h >= screenFrame.height - 1 {
                return true
            }
        }
        return false
    }
}
