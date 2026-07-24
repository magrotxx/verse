import SwiftUI

/// Task 5 STUB: a dark-gray capsule at `model.pillOrigin`, draggable and
/// clamped to the visible frame. No lyric content, no popup — this only proves
/// the window, hit-testing, drag, persistence and clamping before the real UI
/// lands in Task 6+. The full pill/popup hierarchy replaces this body later.
struct RootPillView: View {
    @ObservedObject var model: AppModel

    /// Pill origin captured at the start of a drag, so translation is applied
    /// against a stable base instead of accumulating rounding drift per frame.
    @State private var dragStartOrigin: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.uiState != .hidden {
                pill
                    // pillOrigin is the pill's top-left in this (top-leading)
                    // panel space, so a plain offset places it directly.
                    .offset(x: model.pillOrigin.x, y: model.pillOrigin.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pill: some View {
        let h = model.pillLayout.pillHeight
        return Capsule(style: .continuous)
            .fill(Color(white: 0.15))
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
            .frame(width: model.pillWidth, height: h)
            .contentShape(Capsule())
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
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
