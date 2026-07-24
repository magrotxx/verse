#if DEBUG
import AppKit

/// Coordinate-space + anchor-math checks for `PillLayout` — the pill/popup
/// geometry that has no live-NSScreen dependency. Locks the two flips
/// (screen↔panel, panel↔hit), revision A's edge-anchor rules (screen-third
/// classification, anchored-edge frames, clamping) and the dynamic-width
/// formula. Run via `swift run Verse --checks`.
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

    // MARK: default placement — centered anchor just under the menu bar
    check("defaultAnchor: center mode at the visible midpoint, 8pt down") {
        let d = PillLayout.defaultAnchor(visible: visible)
        return d.mode == .center && approx(d.anchor.x, 720) && approx(d.anchor.y, 33)
    }

    // MARK: revision A — screen-third anchor classification (pill CENTER x)
    check("anchorMode: left third → leading") {
        PillLayout.anchorMode(forCenterX: 200, visible: visible) == .leading
    }
    check("anchorMode: middle third → center") {
        PillLayout.anchorMode(forCenterX: 720, visible: visible) == .center
    }
    check("anchorMode: right third → trailing") {
        PillLayout.anchorMode(forCenterX: 1300, visible: visible) == .trailing
    }
    check("anchorMode: exact third boundaries fall to center") {
        PillLayout.anchorMode(forCenterX: 480, visible: visible) == .center
            && PillLayout.anchorMode(forCenterX: 960, visible: visible) == .center
    }

    // MARK: revision A — anchored-edge frame math (all three modes)
    check("leftEdge: leading pins the left edge at the anchor") {
        approx(PillLayout.leftEdge(anchorX: 500, mode: .leading, width: 200), 500)
    }
    check("leftEdge: center splits the width about the anchor") {
        approx(PillLayout.leftEdge(anchorX: 500, mode: .center, width: 200), 400)
    }
    check("leftEdge: trailing pins the right edge at the anchor") {
        approx(PillLayout.leftEdge(anchorX: 500, mode: .trailing, width: 200), 300)
    }
    check("anchorX(forLeftEdge:) inverts leftEdge in every mode") {
        let modes: [PillAnchorMode] = [.leading, .center, .trailing]
        return modes.allSatisfy { mode in
            let left = PillLayout.leftEdge(anchorX: 500, mode: mode, width: 200)
            return approx(PillLayout.anchorX(forLeftEdge: left, mode: mode, width: 200), 500)
        }
    }
    check("pillFrame: trailing anchor (500,100) w200 → frame x=300") {
        let f = layout.pillFrame(anchor: CGPoint(x: 500, y: 100), mode: .trailing, width: 200)
        return approx(f.minX, 300) && approx(f.minY, 100)
            && approx(f.width, 200) && approx(f.height, 30)
    }
    check("anchored edge stays put as width changes (trailing growth is leftward)") {
        let narrow = layout.pillFrame(anchor: CGPoint(x: 500, y: 100), mode: .trailing, width: 100)
        let wide = layout.pillFrame(anchor: CGPoint(x: 500, y: 100), mode: .trailing, width: 300)
        return approx(narrow.maxX, 500) && approx(wide.maxX, 500) && approx(wide.minX, 200)
    }

    // MARK: revision A — anchor clamping (clamp the LEFT edge, convert back)
    check("clampedAnchor: trailing pill off the left edge snaps to the margin") {
        // anchor 100 w200 → left −100; clamp left to 12 → anchor 212.
        let a = layout.clampedAnchor(
            CGPoint(x: 100, y: 400), mode: .trailing, width: 200, visible: visible)
        return approx(a.x, 212) && approx(a.y, 400)
    }
    check("clampedAnchor: leading pill off the right edge snaps back inside") {
        // left = anchor = 1400, maxLeft = 1440−200−12 = 1228.
        let a = layout.clampedAnchor(
            CGPoint(x: 1400, y: 400), mode: .leading, width: 200, visible: visible)
        return approx(a.x, 1228)
    }
    check("clampedAnchor: y clamps into the visible band") {
        let top = layout.clampedAnchor(
            CGPoint(x: 720, y: -50), mode: .center, width: 200, visible: visible)
        let bottom = layout.clampedAnchor(
            CGPoint(x: 720, y: 5000), mode: .center, width: 200, visible: visible)
        // minY = 25+12 = 37; maxY = 830−30−12 = 788.
        return approx(top.y, 37) && approx(bottom.y, 788)
    }
    check("clampedAnchor: an in-bounds anchor is left untouched") {
        let a = layout.clampedAnchor(
            CGPoint(x: 720, y: 400), mode: .center, width: 200, visible: visible)
        return approx(a.x, 720) && approx(a.y, 400)
    }

    // MARK: revision A — dynamic width formula
    check("pillWidth(forTextWidth:): text + 32pt padding") {
        approx(PillLayout.pillWidth(forTextWidth: 50, maxWidth: 460), 82)
    }
    check("pillWidth(forTextWidth:): never narrower than the ball") {
        approx(PillLayout.pillWidth(forTextWidth: -10, maxWidth: 460), PillLayout.ballDiameter)
    }
    check("pillWidth(forTextWidth:): clamps to the max") {
        approx(PillLayout.pillWidth(forTextWidth: 800, maxWidth: 460), 460)
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
        let pill = CGRect(x: 490, y: 100, width: 460, height: 30)
        let r = layout.popupRect(pillFrame: pill, visible: visible)
        return approx(r.minY, 100) && approx(r.height, 248)
    }
    check("popupRect: bottom-half pill grows the popup upward from its bottom") {
        // midY = 25 + 805/2 = 427.5; y=700 is below it → grow up.
        // popup bottom aligns with pill bottom: rawY = 730 − 248 = 482.
        let pill = CGRect(x: 490, y: 700, width: 460, height: 30)
        let r = layout.popupRect(pillFrame: pill, visible: visible)
        return approx(r.minY, 482) && approx(r.maxY, 730)
    }
    check("popupRect: horizontal center clamps to the visible margin") {
        // A narrow pill at the right edge would center the popup past
        // maxX (1440 − 400 − 12 = 1028); it must clamp there.
        let pill = CGRect(x: 1300, y: 100, width: 100, height: 30)
        let r = layout.popupRect(pillFrame: pill, visible: visible)
        return approx(r.minX, 1028)
    }
}

private func approx(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.01) -> Bool {
    abs(a - b) <= eps
}
#endif
