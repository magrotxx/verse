import SwiftUI
import AppKit

/// Root of the floating-pill hierarchy. Owns the morph namespace and positions
/// the pill / popup inside the full-screen panel. Pill and popup are mutually
/// exclusive and share the `"currentLyric"` matched-geometry id, so toggling
/// `uiState` (with the container's spring) morphs the pill's lyric into the
/// popup's current line and back — the same pattern the old notch UI used for
/// compact ↔ expanded. Everything is unmounted while `.hidden`.
struct RootPillView: View {
    @ObservedObject var model: AppModel

    @Namespace private var morph

    /// Pill origin captured at drag start so translation applies against a
    /// stable base instead of accumulating per-frame rounding drift.
    @State private var dragStartOrigin: CGPoint?

    /// Quick press-bounce on double-click (1 → 0.94 → 1 spring).
    @State private var bounceScale: CGFloat = 1

    /// One-shot inflate-from-a-dot, fired ONLY when the pill appears from
    /// `.hidden` (music starts) — not when collapsing back from the popup,
    /// which is a morph. The pill's opacity transition hides the first frame,
    /// so there is no scale flash before this animates in.
    @State private var appearScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch model.uiState {
            case .hidden:
                EmptyView()
            case .pill:
                pillContainer.transition(.opacity)
            case .popup:
                popupContainer.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.uiState)
        .onChange(of: model.uiState) { old, new in
            if old == .hidden && new == .pill {
                appearScale = 0.12
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appearScale = 1 }
            }
        }
    }

    // MARK: - Pill

    private var pillContainer: some View {
        TimelineView(.animation) { context in
            PillView(
                model: model,
                morph: morph,
                t: model.lyricPosition(),
                wall: context.date.timeIntervalSinceReferenceDate
            )
        }
        // Scales BEFORE the offset, so both bounce and inflate anchor at the
        // pill's own center rather than the panel corner.
        .scaleEffect(bounceScale * appearScale)
        .gesture(
            ExclusiveGesture(
                TapGesture(count: 2).onEnded {
                    model.togglePlayPause()
                    triggerBounce()
                },
                TapGesture(count: 1).onEnded { expand() }
            )
        )
        .simultaneousGesture(dragGesture)
        .contextMenu { PillContextMenu(model: model) }
        .offset(x: model.pillOrigin.x, y: model.pillOrigin.y)
    }

    // MARK: - Popup

    private var popupContainer: some View {
        let rect = model.pillLayout.popupRect(
            pillOrigin: model.pillOrigin, pillWidth: model.pillWidth, visible: model.pillVisibleRect
        )
        return PopupView(model: model, morph: morph)
            .offset(x: rect.minX, y: rect.minY)
    }

    // MARK: - Actions

    private func expand() {
        guard model.uiState == .pill else { return }
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
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                let base = dragStartOrigin ?? model.pillOrigin
                if dragStartOrigin == nil { dragStartOrigin = base }
                model.pillOrigin = CGPoint(
                    x: base.x + value.translation.width,
                    y: base.y + value.translation.height
                )
                model.clampPillOrigin(to: model.pillVisibleRect)
            }
            .onEnded { _ in
                dragStartOrigin = nil
                model.clampPillOrigin(to: model.pillVisibleRect)
            }
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
