import SwiftUI

/// What the pill shows at one instant. The *selection* is a pure function of
/// playback time and the lyric data (`PillDisplay.at`), so it can be exercised
/// by the `--checks` runner without any SwiftUI/AppKit; `PillView` only turns
/// the choice into pixels.
enum PillDisplay: Equatable {
    case ball                     // idle: no track loaded, or hidden-until-next-song
    case title                    // pre-first-line, plain lyrics, or none found
    case chunk(LyricChunk)        // active synced chunk
    case echo(LyricChunk)         // active chunk that is a bracketed ad-lib
    case instrumental(tiny: Bool) // break >3s: rising notes (tiny capsule >15s)
    case blank                    // brief (<3s) inter-line gap

    /// Pick the pill's content at time `t`.
    /// - No track (or user hid until next song) → the idle ball.
    /// - Instrumental gaps: >15s → tiny, >3s → instrumental, else blank.
    static func at(
        t: TimeInterval,
        content: LyricsContent,
        chunks: [LyricChunk],
        duration: TimeInterval,
        trackLoaded: Bool,
        hiddenUntilTrackChange: Bool
    ) -> PillDisplay {
        guard trackLoaded, !hiddenUntilTrackChange else { return .ball }
        switch content {
        case .none, .plain:
            return .title
        case .instrumental:
            return .instrumental(tiny: false)
        case .synced(let timeline):
            guard let first = chunks.first else { return .title }
            if t < first.start { return .title }            // pre-first-line
            if let active = LyricChunker.activeChunk(in: chunks, at: t) {
                return isEcho(active, lines: timeline.lines) ? .echo(active) : .chunk(active)
            }
            let gap = gapLength(chunks: chunks, t: t, duration: duration)
            if gap > 15 { return .instrumental(tiny: true) }
            if gap > 3 { return .instrumental(tiny: false) }
            return .blank
        }
    }

    /// A chunk is an echo when all its words are bracketed, or its backing line
    /// is a whole-line echo.
    static func isEcho(_ chunk: LyricChunk, lines: [LyricLine]) -> Bool {
        if !chunk.words.isEmpty && chunk.words.allSatisfy(\.isEcho) { return true }
        return lines.first(where: { $0.id == chunk.lineIndex })?.isEcho ?? false
    }

    /// Total length of the instrumental gap surrounding `t` (previous chunk end
    /// → next chunk start). Chunks are sorted by start, so one pass finds both.
    static func gapLength(chunks: [LyricChunk], t: TimeInterval, duration: TimeInterval) -> TimeInterval {
        var prevEnd: TimeInterval = 0
        var nextStart: TimeInterval = duration > 0 ? duration : (t + 30)
        for c in chunks {
            if c.start <= t {
                prevEnd = max(prevEnd, c.end)
            } else {
                nextStart = c.start
                break
            }
        }
        return max(nextStart - prevEnd, 0)
    }
}

/// The floating pill (design revision A): translucent BLACK glass — no album
/// wash, no accent glow; the album palette colors only the lyric text. Width is
/// dynamic (model-owned, spring-animated) and the capsule contracts to a ball
/// when idle.
///
/// Per-frame content swaps are driven by playback time `t` and faded with
/// `chunkFade` — never SwiftUI `.transition`s: an `.id`/`.transition` swap
/// strands outgoing views mid-transition inside a `TimelineView`'s per-frame
/// re-renders, whereas an opacity derived from `t` is glitch-proof. `wall` is a
/// live wall-clock feed for the paused breathing pulse and the rising notes,
/// which must keep moving even though `t` freezes while paused.
struct PillView: View {
    @ObservedObject var model: AppModel
    let t: TimeInterval       // lyric/playback time (frozen when paused)
    let wall: TimeInterval    // live wall-clock seconds

    var body: some View {
        let display = currentDisplay()
        let isBall = display == .ball
        return contentView(display)
            .frame(width: model.pillWidth, height: model.pillLayout.pillHeight)
            .background(glass)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
            // Paused: dim to 60%, perfectly still (breathing pulse removed —
            // user decision 2026-07-25).
            .opacity(model.isPaused && !isBall ? 0.6 : 1)
            // Dynamic width: near-critically-damped spring between per-line
            // targets (matches the anchor spring in RootPillView so offset and
            // width read as one motion).
            .animation(Motion.spring(0.45, 0.92), value: model.pillWidth)
            // Width recompute is a per-line event: fires when the displayed
            // chunk/state changes, never per frame.
            .onChange(of: widthKey(display), initial: true) { model.refreshPillWidth() }
    }

    private func currentDisplay() -> PillDisplay {
        PillDisplay.at(
            t: t, content: model.content,
            chunks: model.compactChunks, duration: model.now?.duration ?? 0,
            trackLoaded: model.now != nil,
            hiddenUntilTrackChange: model.hiddenUntilTrackChange
        )
    }

    /// Collapses a display to the identity that decides pill width — the model
    /// re-measures only when this changes.
    private func widthKey(_ display: PillDisplay) -> String {
        switch display {
        case .ball: return "ball"
        case .title: return "title|\(model.pillTitleText)"
        case .chunk(let chunk): return "chunk|\(chunk.id)"
        case .echo(let chunk): return "echo|\(chunk.id)"
        case .instrumental(let tiny): return tiny ? "notes-tiny" : "notes"
        case .blank: return "blank"
        }
    }

    // MARK: - Glass (revision A: neutral black, no album tint)

    private var glass: some View {
        ZStack {
            GlassBackground()
            Color.black.opacity(0.6)
        }
    }

    // MARK: - Content views

    @ViewBuilder
    private func contentView(_ display: PillDisplay) -> some View {
        switch display {
        case .ball:             ballView
        case .title:            titleView
        case .chunk(let chunk): chunkView(chunk)
        case .echo(let chunk):  echoView(chunk)
        case .instrumental:     RisingNotes(t: wall)
        case .blank:            Color.clear
        }
    }

    /// Idle ball: a translucent music note in a 30pt circle (the capsule at
    /// ball width IS a circle). Static — nothing animates while nothing plays.
    private var ballView: some View {
        Image(systemName: "music.note")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
    }

    private var titleView: some View {
        Text(model.pillTitleText)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(model.palette.bright.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
    }

    private func chunkView(_ chunk: LyricChunk) -> some View {
        LyricLineRenderer(
            words: chunk.words, text: chunk.text,
            start: chunk.start, end: chunk.end,
            theme: model.theme, style: .pill(model.palette), t: t
        )
        .opacity(chunkFade(chunk))
        .padding(.horizontal, 16)
    }

    /// Echo (bracketed ad-lib) line: italic serif at 75% size / 55% brightness,
    /// no theme animation — just a time-fade so it drifts in and out softly.
    private func echoView(_ chunk: LyricChunk) -> some View {
        Text(chunk.text)
            .font(.system(size: 13 * 0.75, weight: .regular, design: .serif).italic())
            .foregroundStyle(model.palette.bright.opacity(0.55))
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(chunkFade(chunk))
            .padding(.horizontal, 16)
    }

    // MARK: - Time-driven crossfade

    /// 0→1 over the chunk's first 0.25s, 1→0 over its last 0.25s — adjacent
    /// chunks read as a soft swap; the line's last chunk fades into the gap.
    private func chunkFade(_ chunk: LyricChunk) -> Double {
        guard chunk.end > chunk.start else { return 0 }
        let ramp = min(0.25, (chunk.end - chunk.start) / 2)
        let fadeIn = (t - chunk.start) / ramp
        let fadeOut = (chunk.end - t) / ramp
        return max(0, min(1, min(fadeIn, fadeOut)))
    }
}

/// Instrumental-break animation (revision A): small music notes rising out of
/// the contracted capsule, drifting upward ~9pt while fading in and out,
/// staggered thirds of a ~2.2s loop. A pure function of `t` (wall clock) — no
/// SwiftUI transitions, safe inside TimelineView.
struct RisingNotes: View {
    let t: TimeInterval

    private static let period: TimeInterval = 2.2

    var body: some View {
        if Motion.reduce {
            // Reduce Motion: one calm static note, no drift choreography.
            Image(systemName: "music.note")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        } else {
            ZStack {
                note(index: 0, x: -9, size: 8)
                note(index: 1, x: 0.5, size: 9.5)
                note(index: 2, x: 9, size: 8)
            }
        }
    }

    private func note(index: Int, x: CGFloat, size: CGFloat) -> some View {
        let p = phase(index)
        return Image(systemName: "music.note")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .offset(x: x, y: rise(p))
            .opacity(fade(p))
    }

    /// Staggered 0→1 loop progress for each note.
    private func phase(_ index: Int) -> Double {
        let shifted = t / Self.period + Double(index) / 3.0
        return shifted - shifted.rounded(.down)
    }

    /// Drift upward ~9pt across the loop.
    private func rise(_ p: Double) -> CGFloat {
        CGFloat(4.5 - 9.0 * p)
    }

    /// Fade in then out (sine bump).
    private func fade(_ p: Double) -> Double {
        sin(p * .pi) * 0.9
    }
}
