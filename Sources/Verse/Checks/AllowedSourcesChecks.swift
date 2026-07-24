#if DEBUG
import Foundation

/// Allowlist rules for now-playing sources (2026-07-25 expansion): native
/// music apps always pass; browsers pass only with web players enabled AND
/// music-shaped metadata (artist + album — plain videos publish neither).
func runAllowedSourcesChecks() {
    func state(bundle: String, artist: String = "", album: String = "") -> NowPlayingState {
        NowPlayingState(
            title: "Song", artist: artist, album: album,
            duration: 200, isPlaying: true,
            bundleIdentifier: bundle, artwork: nil
        )
    }

    check("isAllowed: Spotify and Apple Music always pass") {
        NowPlayingCoordinator.isAllowed(state(bundle: "com.spotify.client"), webPlayersEnabled: false)
            && NowPlayingCoordinator.isAllowed(state(bundle: "com.apple.Music"), webPlayersEnabled: false)
    }
    check("isAllowed: YouTube Music desktop app passes") {
        NowPlayingCoordinator.isAllowed(
            state(bundle: "com.github.th-ch.youtube-music"), webPlayersEnabled: false)
    }
    check("isAllowed: browser with artist+album passes when web players on") {
        NowPlayingCoordinator.isAllowed(
            state(bundle: "com.google.Chrome", artist: "Tyler", album: "IGOR"),
            webPlayersEnabled: true)
    }
    check("isAllowed: browser WITHOUT album (plain video) is rejected") {
        !NowPlayingCoordinator.isAllowed(
            state(bundle: "com.google.Chrome", artist: "Some Channel"),
            webPlayersEnabled: true)
    }
    check("isAllowed: browser rejected when web players toggled off") {
        !NowPlayingCoordinator.isAllowed(
            state(bundle: "com.apple.Safari", artist: "Tyler", album: "IGOR"),
            webPlayersEnabled: false)
    }
    check("isAllowed: unknown apps (video players, calls) are rejected") {
        !NowPlayingCoordinator.isAllowed(state(bundle: "us.zoom.xos"), webPlayersEnabled: true)
            && !NowPlayingCoordinator.isAllowed(
                state(bundle: "com.colliderli.iina", artist: "a", album: "b"), webPlayersEnabled: true)
    }
}
#endif
