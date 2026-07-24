import SwiftUI
import AppKit

/// Root of the floating-pill hierarchy. Owns the morph namespace and positions
/// the pill / popup inside the full-screen panel. Pill and popup are mutually
/// exclusive and share the `"currentLyric"` matched-geometry id, so toggling
/// `uiState` (with the container's spring) morphs the pill's lyric into the
/// popup's current line and back.
///
/// ## Side parking (2026-07-25, supersedes revision A's thirds rule)
///
/// `model.pillAnchor` is the ANCHOR point (anchored-edge x + top y) on the
/// LEFT or RIGHT rail. The pill's offset is continuous math of
/// anchor/mode/width (`PillLayout.leftEdge`), and offset + width share one
/// spring — the anchored (rail) edge stays visually stationary while the
/// capsule grows inward. Drops glide to the nearer rail (`snapToRail`).
///
/// ## Battery (Task 9)
///
/// The per-frame `TimelineView` mounts ONLY while something animates: idle
/// (ball, no music) renders a static `PillView` with no timeline at all, and
/// live timelines honor `model.frameInterval` (30fps cap in Low Power Mode).
struct RootPillView: View {
    @ObservedObject var model: AppModel

    @Namespace private var morph

    /// Anchor + mode captured at drag start so translation applies against a
    /// stable base instead of accumulating per-frame rounding drift.
    @State private var dragBase: (anchor: CGPoint, mode: PillAnchorMode)?

    /// Quick press-bounce on double-click (1 → 0.94 → 1 spring).
    @State private var bounceScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch model.uiState {
            case .pill:
                pillContainer.transition(.opacity)
            case .popup:
                popupContainer.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.spring(0.45, 0.85), value: model.uiState)
    }

    // MARK: - Pill (anchored container)

    private var pillContainer: some View {
        pillBody
            .scaleEffect(bounceScale)
            // Exclusive tap so a double-click NEVER also fires the single-click
            // (which would open-then-close the popup). Drag is simultaneous so
            // it coexists with taps; 3pt threshold keeps taps from jittering.
            // Clicks are inert while no track is loaded (idle ball) — revision A.
            .gesture(
                ExclusiveGesture(
                    TapGesture(count: 2).onEnded {
                        guard model.now != nil else { return }
                        model.togglePlayPause()
                        triggerBounce()
                    },
                    TapGesture(count: 1).onEnded { expand() }
                )
            )
            .simultaneousGesture(dragGesture)
            .contextMenu { PillContextMenu(model: model) }
            // Direct anchored placement: the offset is continuous math of
            // anchor/mode/width, and offset + width share one spring, so the
            // anchored edge stays put through width changes with no
            // (unanimatable) Alignment flip — this is what keeps size
            // transitions smooth. No anchor spring while a drag is live: the
            // pill must track the pointer 1:1.
            .offset(
                x: PillLayout.leftEdge(
                    anchorX: model.pillAnchor.x, mode: model.pillAnchorMode, width: model.pillWidth
                ),
                y: model.pillAnchor.y
            )
            .animation(dragBase == nil ? Motion.spring(0.45, 0.92) : nil, value: model.pillAnchor)
            .animation(Motion.spring(0.45, 0.92), value: model.pillWidth)
    }

    /// The pill itself, with a TimelineView mounted only when needed:
    /// - first-run demo (no music yet): demo loop timeline
    /// - idle ball: STATIC view, no timeline, zero per-frame work
    /// - playing/paused song: the live lyric timeline
    @ViewBuilder
    private var pillBody: some View {
        if model.isFirstRunDemo && model.now == nil {
            TimelineView(.animation(minimumInterval: model.frameInterval)) { context in
                DemoPill(model: model, wall: context.date.timeIntervalSinceReferenceDate)
            }
        } else if model.showsIdleBall {
            PillView(model: model, morph: morph, t: 0, wall: 0)
        } else {
            TimelineView(.animation(minimumInterval: model.frameInterval)) { context in
                PillView(
                    model: model,
                    morph: morph,
                    t: model.lyricPosition(),
                    wall: context.date.timeIntervalSinceReferenceDate
                )
            }
        }
    }

    // MARK: - Popup

    private var popupContainer: some View {
        let pillFrame = model.pillLayout.pillFrame(
            anchor: model.pillAnchor, mode: model.pillAnchorMode, width: model.pillWidth
        )
        let rect = model.pillLayout.popupRect(pillFrame: pillFrame, visible: model.pillVisibleRect)
        return PopupView(model: model, morph: morph)
            .offset(x: rect.minX, y: rect.minY)
    }

    // MARK: - Actions

    private func expand() {
        guard model.uiState == .pill, model.now != nil else { return }
        model.uiState = .popup
        // Load-bearing (Task 3 review): opening the popup re-anchors the clock,
        // recovering from the poller's TCC-denial give-up state.
        model.resyncNow()
    }

    private func triggerBounce() {
        guard !Motion.reduce else { return }   // scale choreography off under Reduce Motion
        bounceScale = 0.94
        withAnimation(Motion.spring(0.3, 0.5)) { bounceScale = 1 }
    }

    /// Manual drag in GLOBAL space: measuring translation in a space that does
    /// NOT move with the pill avoids the classic offset↔gesture feedback jitter.
    /// The anchor MODE stays fixed during the drag; at drag-end the mode is
    /// reclassified from the pill center's screen third and the anchor point is
    /// converted so the pill does not move (same left edge, new anchor edge).
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                let base = dragBase ?? (model.pillAnchor, model.pillAnchorMode)
                if dragBase == nil { dragBase = base }
                model.pillAnchor = CGPoint(
                    x: base.anchor.x + value.translation.width,
                    y: base.anchor.y + value.translation.height
                )
                model.clampPillAnchor()
            }
            .onEnded { _ in
                dragBase = nil
                snapToRail()
                model.endFirstRunDemo()   // the first drag retires the demo
            }
    }

    /// AssistiveTouch-style drop (2026-07-25): glide to the nearer side rail,
    /// keeping the drop height. Mode + anchor move in one spring transaction —
    /// the offset math is continuous, so the glide is a single smooth motion.
    private func snapToRail() {
        let visible = model.pillVisibleRect
        let frame = model.pillLayout.pillFrame(
            anchor: model.pillAnchor, mode: model.pillAnchorMode, width: model.pillWidth
        )
        let side = PillLayout.snapSide(forCenterX: frame.midX, visible: visible)
        withAnimation(Motion.spring(0.45, 0.82)) {
            model.pillAnchorMode = side
            model.pillAnchor = CGPoint(
                x: PillLayout.railX(side: side, visible: visible, edgeMargin: model.pillLayout.edgeMargin),
                y: frame.minY
            )
            model.clampPillAnchor()
        }
    }
}

/// First-run moment: the pill loops a demo line center-screen with a one-time
/// caption underneath ("drag me"). Same material recipe as the real pill; all
/// timing derives from `wall`, so it is a pure per-frame render.
private struct DemoPill: View {
    @ObservedObject var model: AppModel
    let wall: TimeInterval

    private static let loopLength: TimeInterval = 4.5
    private static let demoWords: [WordTiming] = LyricsTimeline.synthesizeWords(
        text: AppModel.demoText, start: 0.4, end: 4.1
    )

    var body: some View {
        let loop = (wall - model.demoStartWall).truncatingRemainder(dividingBy: Self.loopLength)
        LyricLineRenderer(
            words: Self.demoWords, text: AppModel.demoText,
            start: 0.4, end: 4.1,
            theme: model.theme, style: .pill(model.palette), t: loop
        )
        .padding(.horizontal, 16)
        .frame(width: model.pillWidth, height: model.pillLayout.pillHeight)
        .background(
            ZStack {
                GlassBackground()
                Color.black.opacity(0.6)
            }
        )
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        // One-time caption below the pill; fades out 8s in (time-driven).
        .overlay(alignment: .top) {
            Text("Drag me somewhere comfy — click to open")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()
                .offset(y: model.pillLayout.pillHeight + 10)
                .opacity(captionOpacity)
        }
    }

    /// 1 for the first 8s of the demo, then a quick fade to 0.
    private var captionOpacity: Double {
        let elapsed = wall - model.demoStartWall
        if elapsed < 8 { return 1 }
        return max(0, 1 - (elapsed - 8) / 0.6)
    }
}

/// Right-click menu on the pill.
struct PillContextMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Menu("Theme") {
            Picker("Theme", selection: $model.theme) {
                ForEach(LyricTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.inline)   // 4 options, checkmark on the current theme
        }

        Menu("Lyric timing") {
            Button("−0.5s") { model.adjustSyncOffset(by: -0.5) }
            Button("−0.1s") { model.adjustSyncOffset(by: -0.1) }
            Button("Reset")  { model.syncOffset = 0 }
            Button("+0.1s") { model.adjustSyncOffset(by: 0.1) }
            Button("+0.5s") { model.adjustSyncOffset(by: 0.5) }
        }

        Divider()
        Button("Hide until next song") { model.hideUntilNextTrack() }
        Divider()
        Button("Settings…") { model.openSettings?() }
        Button("Quit Verse") { NSApp.terminate(nil) }
    }
}
