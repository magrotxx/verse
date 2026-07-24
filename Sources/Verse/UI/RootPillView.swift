import SwiftUI
import AppKit

/// Root of the floating-pill hierarchy. Owns the morph namespace (pill ↔ popup,
/// wired in Task 8) and positions the pill inside the full-screen panel by
/// `model.pillOrigin`. A single `TimelineView(.animation)` per-frame clock feeds
/// both the lyric time and a live wall clock down to `PillView`; it is unmounted
/// entirely while `.hidden`, so nothing animates when no song is playing.
struct RootPillView: View {
    @ObservedObject var model: AppModel

    @Namespace private var morph

    /// Pill origin captured at drag start so translation applies against a
    /// stable base instead of accumulating per-frame rounding drift.
    @State private var dragStartOrigin: CGPoint?

    /// Quick press-bounce on double-click (1 → 0.94 → 1 spring).
    @State private var bounceScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.uiState != .hidden {
                pillContainer
                    // Appear/disappear = a STATE change, so a SwiftUI spring is
                    // correct here (unlike per-frame content crossfades). The
                    // pill inflates from a ~dot and deflates back.
                    .transition(.scale(scale: 0.12, anchor: .center).combined(with: .opacity))
            }
            if model.uiState == .popup {
                placeholderPopup   // Task 8 replaces this with the real PopupView + morph
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.uiState)
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
        .scaleEffect(bounceScale)
        // Exclusive tap so a double-click NEVER also fires the single-click
        // (which would open-then-close the popup). Drag is simultaneous so it
        // coexists with taps; 3pt threshold keeps a tap from registering as one.
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
        // pillOrigin is this view's top-left panel-space point.
        .offset(x: model.pillOrigin.x, y: model.pillOrigin.y)
    }

    // MARK: - Popup placeholder (Task 8 → PopupView with the shared-element morph)

    private var placeholderPopup: some View {
        let rect = model.pillLayout.popupRect(
            pillOrigin: model.pillOrigin, pillWidth: model.pillWidth, visible: model.pillVisibleRect
        )
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(model.palette.background.opacity(0.85))
            .overlay(
                Text("popup — Task 8")
                    .font(.system(size: 12))
                    .foregroundStyle(model.palette.muted)
            )
            .frame(width: rect.width, height: rect.height)
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .offset(x: rect.minX, y: rect.minY)
            .onTapGesture { model.uiState = .pill }   // temporary close-on-click
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
