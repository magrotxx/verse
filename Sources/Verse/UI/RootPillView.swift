import SwiftUI

/// Root of the floating-pill hierarchy. Owns the morph namespace (pill ↔ popup
/// in Task 8) and positions the pill inside the full-screen panel by
/// `model.pillOrigin`. A single `TimelineView(.animation)` per-frame clock feeds
/// both the lyric time and a live wall clock down to `PillView`; it is unmounted
/// entirely while `.hidden`, so nothing animates when no song is playing.
struct RootPillView: View {
    @ObservedObject var model: AppModel

    @Namespace private var morph

    /// Pill origin captured at drag start so translation applies against a
    /// stable base instead of accumulating per-frame rounding drift.
    @State private var dragStartOrigin: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.uiState != .hidden {
                TimelineView(.animation) { context in
                    PillView(
                        model: model,
                        morph: morph,
                        t: model.lyricPosition(),
                        wall: context.date.timeIntervalSinceReferenceDate
                    )
                }
                .gesture(dragGesture)
                // pillOrigin is this view's top-left panel-space point.
                .offset(x: model.pillOrigin.x, y: model.pillOrigin.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Manual drag in GLOBAL space: measuring translation in a space that does
    /// NOT move with the pill avoids the classic offset↔gesture feedback jitter.
    /// 3pt threshold keeps taps (Task 7) from registering as drags.
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
