#if DEBUG
import AppKit

/// Coordinate-space checks for `PillLayout` — the pill/popup geometry that has
/// no live-NSScreen dependency. Locks the two flips (screen↔panel, panel↔hit)
/// and the clamp/placement rules. Run via `swift run Verse --checks`.
func runPillLayoutChecks() {
    let layout = PillLayout()

    // A 1440×900 screen: 25pt menu bar at the top, 70pt dock at the bottom.
    // AppKit is bottom-left, so visibleFrame starts at y=70 and tops out at 875.
    let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let appKitVisible = CGRect(x: 0, y: 70, width: 1440, height: 805)
    // Same area in SwiftUI panel space (top-left): 25pt down from the top.
    let visible = PillLayout.visibleRectInPanelSpace(frame: frame, visible: appKitVisible)

    // MARK: screen space → panel space (Y flip about the panel top)
    check("visibleRectInPanelSpace: menu bar becomes the top inset") {
        approx(visible.minX, 0) && approx(visible.minY, 25)
            && approx(visible.width, 1440) && approx(visible.height, 805)
    }

    // MARK: default placement is top-center, just under the menu bar
    check("defaultOrigin: horizontally centered, 8pt below the menu bar") {
        let o = PillLayout.defaultOrigin(pillWidth: 460, visible: visible)
        return approx(o.x, (1440 - 460) / 2) && approx(o.y, 25 + 8)
    }

    // MARK: clamp keeps the whole pill inside the visible area + edge margin
    check("clampedOrigin: off-screen top-left snaps to the margin corner") {
        let o = layout.clampedOrigin(CGPoint(x: -500, y: -500), pillWidth: 460, visible: visible)
        return approx(o.x, 12) && approx(o.y, 25 + 12)
    }
    check("clampedOrigin: off-screen bottom-right snaps to the far margin") {
        let o = layout.clampedOrigin(CGPoint(x: 5000, y: 5000), pillWidth: 460, visible: visible)
        // maxX = 1440 - 460 - 12 = 968; maxY = (25+805) - 30 - 12 = 788
        return approx(o.x, 968) && approx(o.y, 788)
    }
    check("clampedOrigin: an in-bounds origin is left untouched") {
        let o = layout.clampedOrigin(CGPoint(x: 490, y: 400), pillWidth: 460, visible: visible)
        return approx(o.x, 490) && approx(o.y, 400)
    }

    // MARK: panel space → hit-test space (Y flip about the panel bottom)
    check("hitRect: panel-space top-left flips to AppKit bottom-left") {
        let r = PillLayout.hitRect(
            topLeft: CGPoint(x: 490, y: 33),
            size: CGSize(width: 460, height: 30),
            panelHeight: 900
        )
        // AppKit origin.y = 900 - 33 - 30 = 837; x + size preserved.
        return approx(r.minX, 490) && approx(r.minY, 837)
            && approx(r.width, 460) && approx(r.height, 30)
    }

    // MARK: popup placement — grows down in the top half, up in the bottom half
    check("popupRect: top-half pill grows the popup downward from its top") {
        let r = layout.popupRect(pillOrigin: CGPoint(x: 490, y: 100), pillWidth: 460, visible: visible)
        return approx(r.minY, 100) && approx(r.height, 248)
    }
    check("popupRect: bottom-half pill grows the popup upward from its bottom") {
        // midY = 25 + 805/2 = 427.5; y=700 is below it → grow up.
        // bottom edge aligns with pill bottom: rawY = 700 + 30 - 248 = 482.
        let r = layout.popupRect(pillOrigin: CGPoint(x: 490, y: 700), pillWidth: 460, visible: visible)
        return approx(r.minY, 482) && approx(r.maxY, 730)
    }
    check("popupRect: horizontal center clamps to the visible margin") {
        // A narrow pill pushed to the right edge would center the popup past
        // maxX (1440 - 400 - 12 = 1028); it must clamp there.
        let r = layout.popupRect(pillOrigin: CGPoint(x: 1300, y: 100), pillWidth: 100, visible: visible)
        return approx(r.minX, 1028)
    }
}

private func approx(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.01) -> Bool {
    abs(a - b) <= eps
}
#endif
