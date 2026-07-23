import AppKit

/// Periodically asks the current player for ground-truth playback position
/// via the `osascript` command-line tool, so `PlaybackClock` can correct for
/// interpolation drift between sparse provider updates.
///
/// Deliberately shells out to `/usr/bin/osascript` as a subprocess (rather
/// than `NSAppleScript`, which is main-thread-bound) so every part of this —
/// scheduling, the running-app guard, launching the process, reading its
/// output — happens on a background queue and never touches the main thread.
final class PositionPoller {
    /// Delivered on the poller's background queue — never the main thread.
    var onPosition: ((TimeInterval) -> Void)?

    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "verse.poller", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var activeBundleID: String?
    private var consecutiveFailures = 0
    /// Bundle we stopped polling for good after 3 consecutive failures
    /// (e.g. Automation permission denied while music keeps playing).
    /// Without this the self-stop would be defeated: the coordinator re-fires
    /// `start` on every provider update, which would find `timer == nil`,
    /// reset the failure count, and recreate the timer moments after every
    /// self-stop — flapping forever. Cleared only when `start` is asked for
    /// a *different* bundle, or when a poll for this bundle succeeds again
    /// (which, after a give-up, can only be an explicit `pollOnce` — e.g.
    /// the user granted the Automation permission and reopened the popup).
    private var gaveUpBundleID: String?

    init(interval: TimeInterval = 2.0) {
        self.interval = interval
    }

    /// Starts polling `bundleID` every `interval` seconds. Idempotent while
    /// already polling that same bundle: callers may re-fire this on every
    /// state update (not just play/pause transitions) without resetting —
    /// and thereby starving — the timer's schedule. No-op for a bundle we
    /// gave up on (see `gaveUpBundleID`); asking for a *different* bundle
    /// clears the give-up and starts fresh.
    func start(bundleID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.gaveUpBundleID != bundleID else { return }
            self.gaveUpBundleID = nil
            guard self.activeBundleID != bundleID || self.timer == nil else { return }
            self.timer?.cancel()
            self.activeBundleID = bundleID
            self.consecutiveFailures = 0
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + self.interval, repeating: self.interval)
            t.setEventHandler { [weak self] in self?.poll(bundleID: bundleID) }
            t.resume()
            self.timer = t
        }
    }

    /// Cancels the timer. Safe to call even when not currently polling.
    /// Deliberately leaves any give-up in place — a pause/play cycle must
    /// not grant a persistently failing bundle a fresh set of retries.
    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.activeBundleID = nil
        }
    }

    /// Polls once, immediately, outside the regular schedule — e.g. an
    /// on-demand resync when a popup opens. A success here is also the
    /// recovery path out of a give-up for that bundle.
    func pollOnce(bundleID: String) {
        queue.async { [weak self] in self?.poll(bundleID: bundleID) }
    }

    /// Always runs on `queue` (background). Launches `osascript`, blocks
    /// this utility-queue thread (not the main thread) until it exits, and
    /// parses its stdout as a `Double`.
    private func poll(bundleID: String) {
        // AppleScript LAUNCHES a quit target app on property access, and the
        // provider can keep reporting "playing" for a beat after the user
        // quits the player — an unguarded tick in that window would resurrect
        // the app. Same running-check pattern as AppleScriptNowPlayingProvider;
        // `runningApplications` is safe to read off the main thread.
        guard NSWorkspace.shared.runningApplications
            .contains(where: { $0.bundleIdentifier == bundleID })
        else {
            registerFailure(bundleID: bundleID)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(bundleID)\" to player position"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            registerFailure(bundleID: bundleID)
            return
        }
        // Read to EOF before waiting: for a short-lived process this avoids
        // a pipe-buffer deadlock and guarantees stdout is fully captured.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines)
                  .replacingOccurrences(of: ",", with: "."), // locale decimal comma
              let seconds = Double(text)
        else {
            registerFailure(bundleID: bundleID)
            return
        }
        consecutiveFailures = 0
        if gaveUpBundleID == bundleID { gaveUpBundleID = nil }
        onPosition?(seconds)
    }

    /// Safety net: 3 consecutive failures (app quit, script error, Automation
    /// permission denied, …) cancel the timer AND mark the bundle as given
    /// up, so the coordinator's constant `start` re-fires can't flap the
    /// timer back to life against a target that keeps failing.
    private func registerFailure(bundleID: String) {
        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            timer?.cancel()
            timer = nil
            activeBundleID = nil
            gaveUpBundleID = bundleID
        }
    }
}
