import SwiftUI

/// Colors + font for one rendering context (compact wing vs vibe mode).
struct LyricRenderStyle {
    var font: Font
    var bright: Color
    var dim: Color
    var accent: Color
    var isCompact: Bool

    /// Compact glass-pill line: ~13pt, palette-tinted (bright on dim), same four
    /// theme animations as everywhere else.
    static func pill(_ palette: Palette, size: CGFloat) -> LyricRenderStyle {
        LyricRenderStyle(
            font: .system(size: size, weight: .medium),
            bright: palette.bright,
            dim: palette.bright.opacity(0.30),
            accent: LyricLineRenderer.brandAmber,
            isCompact: true
        )
    }

    /// Popup current line, serif — `size` comes from `FittedFont` so long lines
    /// scale down instead of truncating.
    static func popup(_ palette: Palette, size: CGFloat) -> LyricRenderStyle {
        LyricRenderStyle(
            font: .system(size: size, weight: .semibold, design: .serif),
            bright: palette.bright,
            dim: palette.bright.opacity(0.32),
            accent: LyricLineRenderer.brandAmber,
            isCompact: false
        )
    }
}

/// One renderer, four themes. The same animation language drives BOTH states.
/// Time is sampled per-frame by the caller (inside a TimelineView) and passed
/// in as `t`, so this view is pure.
struct LyricLineRenderer: View {
    let words: [WordTiming]
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let theme: LyricTheme
    let style: LyricRenderStyle
    let t: TimeInterval

    var body: some View {
        switch theme {
        case .lightWipe: wipe
        case .spotlight: spotlight
        case .typeOn: typeOn
        case .tracer: tracer
        }
    }

    // MARK: - Shared timing

    /// 0→1 sweep progress. Derived from word timings weighted by word length,
    /// which equals a constant-speed sweep for synthesized (line-level) data
    /// and snaps to word boundaries when real word-level data exists.
    private var sweepProgress: Double {
        guard !words.isEmpty else {
            let d = max(end - start, 0.3)
            return min(max((t - start) / d, 0), 1)
        }
        let totalChars = words.reduce(0) { $0 + Double($1.text.count + 1) }
        var done = 0.0
        for w in words {
            if t >= w.end {
                done += Double(w.text.count + 1)
            } else if t > w.start {
                let frac = (t - w.start) / max(w.end - w.start, 0.05)
                done += Double(w.text.count + 1) * frac
                break
            } else {
                break
            }
        }
        return min(max(done / max(totalChars, 1), 0), 1)
    }

    private var activeWordIndex: Int? {
        guard t >= start && t < end else { return nil }
        for (i, w) in words.enumerated() where t >= w.start && t < w.end { return i }
        return nil
    }

    // MARK: - Theme 3 (default): light wipe
    // Whole line at ~32% brightness; a wave of full brightness sweeps
    // left→right, synced to the vocal. Animated gradient text mask.

    /// The brand amber the website's hero wipe uses (#E8B168) — the sung text
    /// glows this gold in the default theme, matching the site (user decision
    /// 2026-07-25).
    static let brandAmber = Color(red: 232 / 255, green: 177 / 255, blue: 104 / 255)

    private var wipe: some View {
        let p = sweepProgress
        let feather = 0.10
        // Map p from [0, 1] to [-feather, 1+feather] so the edges are perfectly clear/white
        let mapped = p * (1.0 + feather * 2) - feather
        return ZStack {
            lineText.foregroundStyle(style.dim)
            lineText
                // Gold at the sweep's leading edge, trailing to white behind
                // it — the website hero's exact look. The gradient rides the
                // sweep (`mapped`): text sung a while ago reads white, the
                // word being sung right now glows amber.
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: max(mapped - 0.30, 0)),
                            .init(color: Self.brandAmber, location: max(mapped - 0.02, 0.001)),
                            .init(color: Self.brandAmber, location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: mapped - feather),
                            .init(color: .clear, location: mapped + feather),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        }
    }

    // MARK: - Theme 2: word spotlight
    // All words muted; exactly one bright word at a time, slight scale pop.

    private var spotlight: some View {
        let active = activeWordIndex
        return wordHStack { i, word in
            Text(word.text)
                .font(word.isEcho ? style.font.italic() : style.font)
                // The one lit word carries the brand accent; ad-lib words sit
                // subordinate even when lit.
                .foregroundStyle(i == active ? style.accent : style.dim)
                .opacity(word.isEcho ? 0.8 : 1)
                .scaleEffect(i == active ? 1.06 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: active == i)
        }
    }

    // MARK: - Theme 1: type-on
    // Line starts empty; each word rises in as it's sung. The FULL line is
    // laid out invisibly first (every word always occupies its slot), so
    // spacing and centering never shift as words appear.

    private var typeOn: some View {
        let active = activeWordIndex
        return wordHStack { i, word in
            let revealed = t >= word.start
            Text(word.text)
                .font(word.isEcho ? style.font.italic() : style.font)
                // The word being sung lands in the brand accent, settling to
                // bright once its moment passes; ad-lib words stay subordinate.
                .foregroundStyle(i == active ? style.accent : style.bright)
                .opacity(revealed ? (word.isEcho ? 0.75 : 1) : 0)
                .offset(y: revealed ? 0 : 5)
                .animation(.easeOut(duration: 0.28), value: revealed)
                .animation(.easeOut(duration: 0.35), value: active == i)
        }
    }

    // MARK: - Theme 4: underline tracer
    // Text fully lit and static; a hairline dash slides beneath, tracking
    // playback. Zero motion in the text itself.

    private var tracer: some View {
        let p = sweepProgress
        return lineText
            .foregroundStyle(style.bright)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    let dash: CGFloat = max(geo.size.width * 0.12, 18)
                    Capsule()
                        .fill(style.accent)
                        .frame(width: dash, height: 1.8)
                        .offset(x: (geo.size.width - dash) * p, y: 4)
                        .opacity(p > 0.0 ? 1 : 0)
                }
                .frame(height: 2)
            }
    }

    // MARK: - Helpers

    private var lineText: some View {
        styledLineText
            .font(style.font)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// One Text with inline ad-lib runs italicized (merged background vocals,
    /// "lyric (aaah ooh)"). Run-level italics survive the wipe's outer
    /// foregroundStyle/mask — never set run-level colors here, they would
    /// punch holes in the wipe gradient.
    private var styledLineText: Text {
        guard words.contains(where: { $0.isEcho }) else { return Text(text) }
        var result = Text(verbatim: "")
        for (i, w) in words.enumerated() {
            let piece = Text(verbatim: (i == 0 ? "" : " ") + w.text)
            result = result + (w.isEcho ? piece.font(style.font.italic()) : piece)
        }
        return result
    }

    private func wordHStack<W: View>(
        @ViewBuilder word: @escaping (Int, WordTiming) -> W
    ) -> some View {
        HStack(spacing: spaceWidth) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                word(i, w)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var spaceWidth: CGFloat {
        // Approximate the natural space width for the style's font size.
        style.isCompact ? 3.2 : 5.5
    }
}
