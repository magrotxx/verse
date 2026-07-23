import Foundation

/// Periodically asks the current player for ground-truth playback position
/// via the `osascript` command-line tool, so `PlaybackClock` can correct for
/// interpolation drift between sparse provider updates.
///
/// Deliberately shells out to `/usr/bin/osascript` as a subprocess (rather
/// than `NSAppleScript`, which is main-thread-bound) so every part of this —
/// scheduling, launching the process, reading its output — happens on a
/// background queue and never touches the main thread.
final class PositionPoller {
    /// Delivered on the poller's background queue — never the main thread.
    var onPosition: ((TimeInterval) -> Void)?

    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "verse.poller", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var activeBundleID: String?
    private var consecutiveFailures = 0

    init(interval: TimeInterval = 2.0) {
        self.interval = interval
    }

    /// Starts polling `bundleID` every `interval` seconds. Idempotent while
    /// already polling that same bundle: callers may re-fire this on every
    /// state update (not just play/pause transitions) without resetting —
    /// and thereby starving — the timer's schedule.
    func start(bundleID: String) {
        queue.async { [weak self] in
            guard let self else { return }
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
    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.activeBundleID = nil
        }
    }

    /// Polls once, immediately, outside the regular schedule — e.g. an
    /// on-demand resync when a popup opens.
    func pollOnce(bundleID: String) {
        queue.async { [weak self] in self?.poll(bundleID: bundleID) }
    }

    /// Always runs on `queue` (background). Launches `osascript`, blocks
    /// this utility-queue thread (not the main thread) until it exits, and
    /// parses its stdout as a `Double`.
    private func poll(bundleID: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(bundleID)\" to player position"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            registerFailure()
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
            registerFailure()
            return
        }
        consecutiveFailures = 0
        onPosition?(seconds)
    }

    /// Safety net: if the app quit between provider updates, every future
    /// tick would otherwise keep addressing a dead (or relaunching) target
    /// forever. Stop after 3 consecutive failures instead.
    private func registerFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            timer?.cancel()
            timer = nil
            activeBundleID = nil
        }
    }
}
