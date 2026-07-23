#if DEBUG
/// Converted from the planned Tests/VerseTests/PlaybackClockTests.swift —
/// same three test cases, same assertions, expressed via `check` (no XCTest
/// on this machine; see Checks.swift).
func runPlaybackClockChecks() {
    // testCorrectIgnoresSmallDrift
    check("correctIgnoresSmallDrift: small drift is a no-op") {
        let clock = PlaybackClock()
        clock.update(elapsed: 10, playing: true, rate: 1, duration: 100)
        return !clock.correct(to: clock.position() + 0.1)
    }

    // testCorrectAppliesLargeDrift
    check("correctAppliesLargeDrift: large drift returns true") {
        let clock = PlaybackClock()
        clock.update(elapsed: 10, playing: true, rate: 1, duration: 100)
        return clock.correct(to: clock.position() + 2.0)
    }
    check("correctAppliesLargeDrift: position lands near corrected target") {
        let clock = PlaybackClock()
        clock.update(elapsed: 10, playing: true, rate: 1, duration: 100)
        _ = clock.correct(to: clock.position() + 2.0)
        return abs(clock.position() - 12) <= 0.3
    }

    // testCorrectRespectsCustomTolerance
    check("correctRespectsCustomTolerance: within custom tolerance is a no-op") {
        let clock = PlaybackClock()
        clock.update(elapsed: 5, playing: false, rate: 1, duration: 100)
        return !clock.correct(to: 5.4, tolerance: 0.5)
    }
    check("correctRespectsCustomTolerance: beyond custom tolerance corrects") {
        let clock = PlaybackClock()
        clock.update(elapsed: 5, playing: false, rate: 1, duration: 100)
        return clock.correct(to: 6.1, tolerance: 0.5)
    }
}
#endif
