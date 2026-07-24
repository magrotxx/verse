import SwiftUI
import AppKit

/// Root of the floating-pill hierarchy. Owns the morph namespace and positions
/// the pill / popup inside the full-screen panel. Pill and popup are mutually
/// exclusive and share the `"currentLyric"` matched-geometry id, so toggling
/// `uiState` (with the container's spring) morphs the pill's lyric into the
/// popup's current line and back.
///
/// ## Edge-anchored placement (revision A)
///
/// `model.pillAnchor` is the ANCHOR point (anchored-edge x + top y). The pill
/// sits inside a fixed-width container (`pillMaxWidth`) aligned to that edge:
/// the container never moves while the pill's width springs between per-line
/// targets, so the anchored edge stays visually stationary — leading-anchored
/// pills grow rightward, trailing leftward, centered symmetric.
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
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.uiState)
    }

    // MARK: - Pill (anchored container)

    private var pillContainer: some View {
        let maxW = model.pillMaxWidth
        let mode = model.pillAnchorMode
        return TimelineView(.animation) { context in
            PillView(
                model: model,
                morph: morph,
                t: model.lyricPosition(),
                wall: context.date.timeIntervalSinceReferenceDate
            )
        }
        .scaleEffect(bounceScale)
        // Exclusive tap so a double-click NEVER also fires the single-click
        // (which would open-then-close the popup). Drag is simultaneous so it
        // coexists with taps; 3pt threshold keeps a tap from registering as one.
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
        // The fixed-width container that realizes the edge anchor: the pill
        // aligns to the anchored edge inside it, and only the pill resizes.
        .frame(width: maxW, height: model.pillLayout.pillHeight, alignment: containerAlignment(mode))
        .offset(x: containerLeft(mode: mode, maxWidth: maxW), y: model.pillAnchor.y)
    }

    private func containerAlignment(_ mode: PillAnchorMode) -> Alignment {
        switch mode {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    /// Panel-space x of the fixed container's left edge — positioned so the
    /// container's anchored edge lands exactly on `pillAnchor.x`.
    private func containerLeft(mode: PillAnchorMode, maxWidth: CGFloat) -> CGFloat {
        switch mode {
        case .leading: return model.pillAnchor.x
        case .center: return model.pillAnchor.x - maxWidth / 2
        case .trailing: return model.pillAnchor.x - maxWidth
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
        bounceScale = 0.94
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { bounceScale = 1 }
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
                reanchorAfterDrag()
            }
    }

    /// Drag-end reclassification: pick the anchor mode from the pill CENTER's
    /// screen third, then convert the anchor x so the frame is unchanged.
    private func reanchorAfterDrag() {
        let width = model.pillWidth
        let frame = model.pillLayout.pillFrame(
            anchor: model.pillAnchor, mode: model.pillAnchorMode, width: width
        )
        let newMode = PillLayout.anchorMode(forCenterX: frame.midX, visible: model.pillVisibleRect)
        if newMode != model.pillAnchorMode {
            model.pillAnchorMode = newMode
            model.pillAnchor = CGPoint(
                x: PillLayout.anchorX(forLeftEdge: frame.minX, mode: newMode, width: width),
                y: frame.minY
            )
        }
        model.clampPillAnchor()
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
