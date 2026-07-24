import SwiftUI

/// What the pill shows at one instant. The *selection* is a pure function of
/// playback time and the lyric data (`PillDisplay.at`), so it can be exercised
/// by the `--checks` runner without any SwiftUI/AppKit; `PillView` only turns
/// the choice into pixels.
enum PillDisplay: Equatable {
    case title              // pre-first-line, plain lyrics, or none found
    case chunk(LyricChunk)  // active synced chunk
    case echo(LyricChunk)   // active chunk that is a bracketed ad-lib
    case dots(tiny: Bool)   // instrumental break (tiny for very long gaps)
    case blank              // brief (<3s) inter-line gap

    /// Pick the pill's content at time `t`.
    /// - Instrumental gaps: >15s → tiny dots, >3s → dots, else blank.
    static func at(
        t: TimeInterval,
        content: LyricsContent,
        chunks: [LyricChunk],
        duration: TimeInterval
    ) -> PillDisplay {
        switch content {
        case .none, .plain:
            return .title
        case .instrumental:
            return .dots(tiny: false)
        case .synced(let timeline):
            guard let first = chunks.first else { return .title }
            if t < first.start { return .title }            // pre-first-line
            if let active = LyricChunker.activeChunk(in: chunks, at: t) {
                return isEcho(active, lines: timeline.lines) ? .echo(active) : .chunk(active)
            }
            let gap = gapLength(chunks: chunks, t: t, duration: duration)
            if gap > 15 { return .dots(tiny: true) }
            if gap > 3 { return .dots(tiny: false) }
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

/// The floating glass pill: the current lyric line (or title / breathing dots),
/// tinted by the album palette.
///
/// Per-frame content swaps are driven by playback time `t` and faded with
/// `chunkFade` — never SwiftUI `.transition`s: an `.id`/`.transition` swap
/// strands outgoing views mid-transition inside a `TimelineView`'s per-frame
/// re-renders, whereas an opacity derived from `t` is glitch-proof. `wall` is a
/// live wall-clock feed for the paused breathing pulse, which must keep moving
/// even though `t` is frozen while paused.
struct PillView: View {
    @ObservedObject var model: AppModel
    var morph: Namespace.ID
    let t: TimeInterval       // lyric/playback time (frozen when paused)
    let wall: TimeInterval    // live wall-clock seconds (paused breathing)

    var body: some View {
        let display = PillDisplay.at(
            t: t, content: model.content,
            chunks: model.compactChunks, duration: model.now?.duration ?? 0
        )
        let width = displayWidth(for: display)
        return contentView(display)
            .frame(width: width, height: model.pillLayout.pillHeight)
            .background(glass)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: model.palette.accent.opacity(0.25), radius: 12)
            // Paused: breathe (live wall time) + dim to 60%.
            .scaleEffect(breathingScale)
            .opacity(model.isPaused ? 0.6 : 1)
            // Instrumental contraction / expansion springs on width only.
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: width)
    }

    // MARK: - Glass + album wash

    private var glass: some View {
        ZStack {
            GlassBackground()
            model.palette.background.opacity(0.35)
        }
    }

    // MARK: - Paused breathing (live wall time; ~3s period, ±1.5% scale)

    private var breathingScale: CGFloat {
        guard model.isPaused else { return 1 }
        return 1 + 0.015 * CGFloat(sin(wall * .pi * 2 / 3))
    }

    // MARK: - Width per state

    private func displayWidth(for display: PillDisplay) -> CGFloat {
        switch display {
        case .dots(let tiny): return tiny ? 56 : 96
        default: return model.pillWidth
        }
    }

    // MARK: - Content views

    @ViewBuilder
    private func contentView(_ display: PillDisplay) -> some View {
        switch display {
        case .title:            titleView
        case .chunk(let chunk): chunkView(chunk)
        case .echo(let chunk):  echoView(chunk)
        case .dots:             dotsView
        case .blank:            Color.clear
        }
    }

    private var titleView: some View {
        Text(titleText)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(model.palette.bright.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
    }

    private var titleText: String {
        guard let now = model.now else { return "" }
        return "♪ \(TitleCleaner.clean(now.title)) — \(now.artist)"
    }

    private func chunkView(_ chunk: LyricChunk) -> some View {
        LyricLineRenderer(
            words: chunk.words, text: chunk.text,
            start: chunk.start, end: chunk.end,
            theme: model.theme, style: .pill(model.palette), t: t
        )
        .opacity(chunkFade(chunk))
        .padding(.horizontal, 16)
        .matchedGeometryEffect(id: "currentLyric", in: morph, isSource: model.uiState != .popup)
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
            .matchedGeometryEffect(id: "currentLyric", in: morph, isSource: model.uiState != .popup)
    }

    private var dotsView: some View {
        BreathingDots(color: model.palette.bright, t: wall)
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

/// Apple Music-style breathing dots for instrumental breaks.
/// (Moved verbatim from VibeModeView so both the pill and popup can use it.)
struct BreathingDots: View {
    let color: Color
    let t: TimeInterval

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .opacity(opacity(for: i))
                    .scaleEffect(scale(for: i))
            }
        }
    }

    private func pulse(for index: Int) -> Double {
        let phase = sin((t * .pi * 2.0 / 2.4) - Double(index) * 0.7)
        return (phase + 1.0) / 2.0
    }

    private func opacity(for index: Int) -> Double {
        0.35 + 0.45 * pulse(for: index)
    }

    private func scale(for index: Int) -> Double {
        0.85 + 0.2 * pulse(for: index)
    }
}
