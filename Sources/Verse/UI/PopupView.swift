import SwiftUI

/// The glass karaoke card the pill unfurls into on click. Ported from the old
/// VibeModeView (3-line follow, scroll-to-browse, scrubber, transport,
/// click-to-seek) onto a translucent glass card with a fitted current-line font
/// and cleaned title. The current-line container is the `matchedGeometryEffect`
/// destination so the pill's lyric morphs into it.
struct PopupView: View {
    @ObservedObject var model: AppModel
    var morph: Namespace.ID

    @State private var scrubberHover = false
    @State private var dragPosition: TimeInterval?

    private var size: CGSize { model.pillLayout.popupSize }

    var body: some View {
        TimelineView(.animation) { _ in
            VStack(spacing: 8) {
                header
                lyricsArea(t: model.lyricPosition())
                    .frame(maxHeight: .infinity)
                scrubber(t: model.position())
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: size.width, height: size.height)
        .background(glass)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }

    /// Revision A: neutral dark glass — the album palette tints only the
    /// content (lyrics, scrubber, buttons), never the material.
    private var glass: some View {
        ZStack {
            GlassBackground()
            Color.black.opacity(0.6)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: { model.openSourcePlayer() }) {
                artwork(size: 36, radius: 9)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(TitleCleaner.clean(model.now?.title ?? ""))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(model.palette.bright)
                    .lineLimit(1)
                Text(model.now?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(model.palette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Icon-only source glyph (album omitted per spec).
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(model.palette.muted)
                .frame(width: 26, height: 26)
                .background(Capsule().fill(model.palette.bright.opacity(0.07)))
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        if let art = model.now?.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(model.palette.bright.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note").foregroundStyle(model.palette.muted)
                )
        }
    }

    // MARK: - Lyrics area

    @ViewBuilder
    private func lyricsArea(t: TimeInterval) -> some View {
        switch model.content {
        case .synced(let timeline):
            if model.browsing {
                browseList(timeline: timeline, t: t)
            } else {
                threeLines(timeline: timeline, t: t)
            }
        case .plain(let text):
            ScrollView(showsIndicators: false) {
                Text(text)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(model.palette.bright.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        case .instrumental:
            instrumentalIndicator(t: t)
        case .none:
            VStack(spacing: 7) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.palette.muted.opacity(0.55))
                Text("No lyrics for this one")
                    .font(.system(size: 12.5, design: .serif).italic())
                    .foregroundStyle(model.palette.muted)
            }
        }
    }

    /// The signature 3-line karaoke view. Continuous sliding (commit 42ada0a):
    /// every windowed line holds both a current-style renderer and a neighbor
    /// label, crossfading by `offset`, and the whole stack springs on `idx`.
    @ViewBuilder
    private func threeLines(timeline: LyricsTimeline, t: TimeInterval) -> some View {
        let idx = timeline.lineIndex(at: t)
        let inBreak = timeline.isInstrumentalBreak(at: t)
        let lines = timeline.lines
        let baseIdx = idx ?? firstLineIndex(lines: lines, after: t) ?? 0

        ZStack {
            // Morph destination: the pill's lyric flies to this anchor.
            Color.clear
                .frame(height: 34)
                .matchedGeometryEffect(id: "currentLyric", in: morph, isSource: model.uiState == .popup)

            if inBreak {
                instrumentalIndicator(t: t, nextStart: timeline.nextLineStart(after: t))
                    .transition(.opacity)
            } else {
                let window = (baseIdx - 1) ... (baseIdx + 1)
                ForEach(window, id: \.self) { i in
                    if lines.indices.contains(i), !lines[i].isEmpty {
                        let offset = i - baseIdx
                        let line = lines[i]

                        ZStack {
                            currentLine(line, t: t)
                                .frame(height: 34)
                                .opacity(offset == 0 ? 1 : 0)
                                .scaleEffect(offset == 0 ? 1 : 0.95)

                            neighborLine(line: line)
                                .opacity(offset == 0 ? 0 : 1)
                                .scaleEffect(offset == 0 ? 1.05 : 1)
                        }
                        .offset(y: CGFloat(offset) * 33.0)
                        .zIndex(offset == 0 ? 1 : 0)
                        .transition(.opacity)
                    }
                }
            }
        }
        .frame(height: 84)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: idx)
    }

    /// The current (center) line: echo lines render as static italic serif;
    /// everything else animates with the active theme at a fit-to-width size.
    @ViewBuilder
    private func currentLine(_ line: LyricLine, t: TimeInterval) -> some View {
        if line.isEcho {
            Text(line.text)
                .font(.system(size: 21.5 * 0.75, weight: .regular, design: .serif).italic())
                .foregroundStyle(model.palette.bright.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            LyricLineRenderer(
                words: line.words, text: line.text,
                start: line.start, end: line.end,
                theme: model.theme,
                style: .popup(model.palette, size: fittedSize(for: line.text)),
                t: t
            )
        }
    }

    /// Fit-to-width current-line size (floor 60% of 21.5 via FittedFont).
    private func fittedSize(for text: String) -> CGFloat {
        FittedFont.pointSize(
            text: text, base: 21.5, weight: .semibold, design: .serif, maxWidth: 360
        )
    }

    private func firstLineIndex(lines: [LyricLine], after t: TimeInterval) -> Int? {
        lines.firstIndex { $0.start > t && !$0.isEmpty }
    }

    @ViewBuilder
    private func neighborLine(line: LyricLine) -> some View {
        Text(line.text)
            .font(.system(size: 14, design: .serif).italic())
            .foregroundStyle(model.palette.mid.opacity(0.35))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 18)
            .contentShape(Rectangle())
            .onTapGesture { model.seek(to: line.start + 0.01) }
    }

    /// Scroll-to-browse: full lyrics list; snaps back after 4s idle.
    private func browseList(timeline: LyricsTimeline, t: TimeInterval) -> some View {
        let currentIdx = timeline.lineIndex(at: t)
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(timeline.lines.filter { !$0.isEmpty }) { line in
                        Text(line.text)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(
                                line.id == currentIdx
                                    ? model.palette.bright
                                    : model.palette.mid.opacity(0.4)
                            )
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.seek(to: line.start + 0.01)
                                model.exitBrowse()
                            }
                            .id(line.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                if let currentIdx { proxy.scrollTo(currentIdx, anchor: .center) }
            }
        }
    }

    // MARK: - Instrumental indicator

    @ViewBuilder
    private func instrumentalIndicator(t: TimeInterval, nextStart: TimeInterval? = nil) -> some View {
        switch model.instrumentalStyle {
        case .breathingDots:
            BreathingDots(color: model.palette.bright, t: t)
        case .countdown:
            if let nextStart, nextStart > t {
                Text("♪ \(Int((nextStart - t).rounded(.up)))s")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(model.palette.muted)
                    .monospacedDigit()
            } else {
                BreathingDots(color: model.palette.bright, t: t)
            }
        case .bigArt:
            artwork(size: 30, radius: 7)
                .scaleEffect(1.0 + 0.06 * sin(t * .pi * 2 / 3.0))
        }
    }

    // MARK: - Scrubber

    private func scrubber(t: TimeInterval) -> some View {
        let duration = max(model.now?.duration ?? 1, 1)
        let shown = dragPosition ?? t
        let progress = min(max(shown / duration, 0), 1)

        return HStack(spacing: 8) {
            Text(timeString(shown))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(model.palette.muted)

            GeometryReader { geo in
                let barHeight: CGFloat = scrubberHover || model.scrubbing ? 6 : 3
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(model.palette.bright.opacity(0.12))
                        .frame(height: barHeight)
                    Capsule()
                        .fill(model.palette.accent)
                        .frame(width: max(geo.size.width * progress, barHeight), height: barHeight)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.15), value: barHeight)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            model.scrubbing = true
                            let frac = min(max(value.location.x / geo.size.width, 0), 1)
                            dragPosition = frac * duration
                        }
                        .onEnded { value in
                            let frac = min(max(value.location.x / geo.size.width, 0), 1)
                            model.seek(to: frac * duration)
                            dragPosition = nil
                            model.scrubbing = false
                        }
                )
            }
            .frame(height: 14)
            .onHover { scrubberHover = $0 }

            Text(timeString(duration))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(model.palette.muted)
        }
    }

    private func timeString(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Controls

    private var controls: some View {
        ZStack {
            HStack(spacing: 22) {
                controlButton("backward.fill", size: 11) { model.previousTrack() }
                controlButton(model.now?.isPlaying == true ? "pause.fill" : "play.fill", size: 15) {
                    model.togglePlayPause()
                }
                controlButton("forward.fill", size: 11) { model.nextTrack() }
            }

            HStack {
                controlButton("paintbrush", size: 11, dim: true) { model.openSettings?() }
                Spacer()
                Button(action: { model.pinned.toggle() }) {
                    Image(systemName: model.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.pinned ? model.palette.accent : model.palette.muted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func controlButton(
        _ symbol: String, size: CGFloat, dim: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(dim ? model.palette.muted : model.palette.bright.opacity(0.9))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Apple Music-style breathing dots — used only by the popup's instrumental
/// indicator now (revision A replaced the pill's dots with `RisingNotes`).
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
