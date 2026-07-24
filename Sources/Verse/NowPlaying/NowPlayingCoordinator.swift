import Foundation

/// Picks the best available now-playing source and exposes a single interface.
/// Preference: MediaRemote adapter (system-wide) → AppleScript polling fallback.
final class NowPlayingCoordinator {
    private var provider: NowPlayingProvider?
    private let clock: PlaybackClock
    private let poller = PositionPoller()

    /// Native music apps that drive the pill (each reports its own bundle ID
    /// through MediaRemote).
    static let musicApps: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
        "com.github.th-ch.youtube-music",   // YouTube Music desktop
        "com.tidal.desktop",
        "com.deezer.deezer-desktop",
        "com.amazon.music",
        "tv.plex.plexamp",
        "com.coppertino.Vox",
        "com.swinsian.Swinsian",
    ]

    /// Browsers whose tabs may host a WEB music player (YT Music, etc.).
    static let browsers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",       // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
    ]

    /// Position re-anchor polling works only for AppleScript-able players.
    static let scriptableSources: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
    ]

    /// Pure allowlist rule (checkable): native music apps always pass; a
    /// browser passes only when web players are enabled AND the metadata
    /// looks like real music — web players (YT Music web…) publish artist AND
    /// album via MediaSession, plain videos/tabs don't. Everything else
    /// (video apps, calls) is ignored.
    static func isAllowed(_ state: NowPlayingState, webPlayersEnabled: Bool) -> Bool {
        if musicApps.contains(state.bundleIdentifier) { return true }
        if browsers.contains(state.bundleIdentifier) {
            return webPlayersEnabled && !state.artist.isEmpty && !state.album.isEmpty
        }
        return false
    }

    private static func isAllowed(_ state: NowPlayingState) -> Bool {
        isAllowed(
            state,
            webPlayersEnabled: UserDefaults.standard.object(forKey: "verse.webPlayers") as? Bool ?? true
        )
    }

    /// bundleID + playing flag from the last *filtered* (allowed-source)
    /// state — this is what the poller is allowed to target. Written from
    /// the provider's background callback, read from `resyncNow()` which may
    /// be called from any thread (e.g. the main actor on popup-open), so
    /// access is lock-guarded.
    private let lastStateLock = NSLock()
    private var lastBundleID: String?
    private var lastIsPlaying = false

    /// Delivered on the main queue.
    var onUpdate: ((NowPlayingState?) -> Void)?

    init(clock: PlaybackClock) {
        self.clock = clock
        poller.onPosition = { [weak self] elapsed in
            self?.clock.correct(to: elapsed)
        }
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let chosen: NowPlayingProvider
            if let adapter = AdapterNowPlayingProvider(), adapter.selfTest() {
                chosen = adapter
                NSLog("Verse: using MediaRemote adapter")
            } else {
                chosen = AppleScriptNowPlayingProvider()
                NSLog("Verse: using AppleScript fallback")
            }
            chosen.onUpdate = { [weak self] rawState, elapsed, rate in
                guard let self else { return }
                let state = rawState.flatMap {
                    Self.isAllowed($0) ? $0 : nil
                }
                let playing = state?.isPlaying ?? false
                // Pause diffs sometimes arrive without elapsedTime, which reaches
                // us as 0 and would clobber the frozen lyric position (the pill
                // then falls back to the title — the first-pause bug). While
                // paused, elapsed ≈ 0 against a clock well past it is missing
                // data, not a seek-to-start: keep the clock's own position.
                // (A real seek-to-0 made while paused catches up on resume.)
                let safeElapsed = (!playing && elapsed <= 0.05 && self.clock.position() > 1)
                    ? self.clock.position() : elapsed
                self.clock.update(
                    elapsed: safeElapsed,
                    playing: playing,
                    rate: rate == 0 ? 1 : rate,
                    duration: state?.duration ?? 0
                )
                self.updateLastState(bundleID: state?.bundleIdentifier, isPlaying: playing)
                // Re-anchor polling only for AppleScript-able players; the
                // rest (YT Music, TIDAL, web players…) ride the adapter's
                // event timestamps.
                if let bundleID = state?.bundleIdentifier, playing,
                   Self.scriptableSources.contains(bundleID) {
                    self.poller.start(bundleID: bundleID)
                } else {
                    self.poller.stop()
                }
                DispatchQueue.main.async { self.onUpdate?(state) }
            }
            self.provider = chosen
            chosen.start()
        }
    }

    func stop() {
        provider?.stop()
        poller.stop()
    }

    func togglePlayPause() { provider?.togglePlayPause() }
    func nextTrack() { provider?.nextTrack() }
    func previousTrack() { provider?.previousTrack() }

    func seek(to seconds: TimeInterval) {
        clock.jump(to: seconds) // instant UI response
        provider?.seek(to: seconds)
    }

    /// Ask the player for ground truth right now instead of waiting for the
    /// next scheduled poll (e.g. call when a popup opens). No-op unless the
    /// last known state says an allowed source is actively playing — never
    /// queries (and so never risks launching) an app we don't already know
    /// is running and playing.
    func resyncNow() {
        guard let bundleID = lastPlayingBundleID(),
              Self.scriptableSources.contains(bundleID) else { return }
        poller.pollOnce(bundleID: bundleID)
    }

    // MARK: - Last-known-state bookkeeping

    private func updateLastState(bundleID: String?, isPlaying: Bool) {
        lastStateLock.lock()
        lastBundleID = bundleID
        lastIsPlaying = isPlaying
        lastStateLock.unlock()
    }

    private func lastPlayingBundleID() -> String? {
        lastStateLock.lock()
        defer { lastStateLock.unlock() }
        return lastIsPlaying ? lastBundleID : nil
    }
}
