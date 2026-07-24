import AppKit

/// Geometry for the floating pill + popup. Every screen-space calculation lives
/// here as a *pure* function so the coordinate math can be exercised by the
/// `--checks` runner without a live `NSScreen`.
///
/// ## Coordinate spaces (READ THIS FIRST)
///
/// Two spaces are in play and they disagree on where `Y = 0` is. Mixing them
/// up is the single easiest way to break the pill's placement, so every
/// conversion below is spelled out.
///
/// * **AppKit / screen space** — origin BOTTOM-left, `Y` grows UP.
///   `NSScreen.frame` and `NSScreen.visibleFrame` live here, and so do the
///   points delivered to `PassThroughHostingView.hitTest(_:)`.
/// * **SwiftUI panel space** — origin TOP-left, `Y` grows DOWN. The full-screen
///   panel's content view spans `screen.frame`; SwiftUI lays the pill out in
///   this space, so `AppModel.pillOrigin` (the pill's top-left corner) is a
///   panel-space point.
///
/// The panel's top edge sits at AppKit `y = frame.maxY`, so converting a `Y`
/// between the two spaces is a flip about that edge:
///
///     swiftUIy = frame.maxY - appKitY          // and the reverse is identical
///
/// `X` only needs the panel's left edge subtracted (`frame.minX`), since both
/// spaces agree that `X` grows rightward.
struct PillLayout {
    var pillHeight: CGFloat = 30
    var popupSize = CGSize(width: 400, height: 248)
    var edgeMargin: CGFloat = 12

    /// The pill never resizes per line; this is the fixed capsule width for a
    /// given screen — `min(38% of screen width, 460)`.
    func pillMaxWidth(screen: NSScreen) -> CGFloat {
        min(screen.frame.width * 0.38, 460)
    }

    // MARK: - Screen space → panel space

    /// `visible` (AppKit bottom-left, excludes menu bar + dock) expressed in
    /// SwiftUI panel space (top-left), given the panel spans `frame`.
    ///
    /// - The visible area's LEFT edge is `visible.minX - frame.minX` in from
    ///   the panel's left edge.
    /// - The visible area's TOP edge (AppKit `visible.maxY`) is
    ///   `frame.maxY - visible.maxY` down from the panel's top edge — this is
    ///   exactly the menu bar height when the screen has one.
    static func visibleRectInPanelSpace(frame: CGRect, visible: CGRect) -> CGRect {
        CGRect(
            x: visible.minX - frame.minX,
            y: frame.maxY - visible.maxY,
            width: visible.width,
            height: visible.height
        )
    }

    static func visibleRectInPanelSpace(screen: NSScreen) -> CGRect {
        visibleRectInPanelSpace(frame: screen.frame, visible: screen.visibleFrame)
    }

    // MARK: - Default placement

    /// Top-center of the visible area, 8pt below the menu bar (panel space).
    static func defaultOrigin(pillWidth: CGFloat, visible: CGRect) -> CGPoint {
        CGPoint(
            x: visible.minX + (visible.width - pillWidth) / 2,
            y: visible.minY + 8
        )
    }

    // MARK: - Clamp

    /// Clamp a panel-space top-left `origin` so the whole pill stays inside
    /// `visible` with `edgeMargin` of breathing room on every edge. Pure.
    func clampedOrigin(_ origin: CGPoint, pillWidth: CGFloat, visible: CGRect) -> CGPoint {
        let minX = visible.minX + edgeMargin
        let maxX = visible.maxX - pillWidth - edgeMargin
        let minY = visible.minY + edgeMargin
        let maxY = visible.maxY - pillHeight - edgeMargin
        return CGPoint(
            x: clampValue(origin.x, minX, max(minX, maxX)),
            y: clampValue(origin.y, minY, max(minY, maxY))
        )
    }

    // MARK: - Panel space → hit-test (AppKit) space

    /// A panel-space top-left rect (`topLeft` + `size`) expressed in the AppKit
    /// (bottom-left) coordinates that `PassThroughHostingView.hitTest(_:)`
    /// receives. `panelHeight` is the hosting view's height (`= frame.height`).
    ///
    /// Only `Y` flips: the shape's TOP edge is `topLeft.y` down from the panel
    /// top, so its BOTTOM edge is `panelHeight - topLeft.y - size.height` up
    /// from the panel bottom — which is the AppKit rect origin.
    static func hitRect(topLeft: CGPoint, size: CGSize, panelHeight: CGFloat) -> CGRect {
        CGRect(
            x: topLeft.x,
            y: panelHeight - topLeft.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Popup placement

    /// The popup rect in panel space (top-left). It grows DOWN from the pill's
    /// top edge when the pill sits in the visible area's top half, else UP from
    /// the pill's bottom edge; horizontally centered on the pill and clamped to
    /// `visible` + `edgeMargin` on every edge. Pure.
    func popupRect(pillOrigin: CGPoint, pillWidth: CGFloat, visible: CGRect) -> CGRect {
        let size = popupSize
        let pillCenterX = pillOrigin.x + pillWidth / 2
        let minX = visible.minX + edgeMargin
        let maxX = visible.maxX - size.width - edgeMargin
        let x = clampValue(pillCenterX - size.width / 2, minX, max(minX, maxX))

        let midY = visible.minY + visible.height / 2
        let growsDown = pillOrigin.y < midY
        let rawY = growsDown ? pillOrigin.y : (pillOrigin.y + pillHeight - size.height)
        let minY = visible.minY + edgeMargin
        let maxY = visible.maxY - size.height - edgeMargin
        let y = clampValue(rawY, minY, max(minY, maxY))

        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// File-local numeric clamp (kept off `Comparable` to avoid touching shared code).
private func clampValue(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(v, lo), hi)
}
