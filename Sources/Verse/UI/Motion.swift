import AppKit
import SwiftUI

/// Central animation policy: every spring in the pill/popup goes through here
/// so the system Reduce Motion setting (Accessibility → Display) can swap all
/// of them for short fades at once. Time-driven choreography (breathing,
/// rising notes, bounce scale) checks `Motion.reduce` directly and collapses
/// to static/opacity-only rendering.
enum Motion {
    /// Live system setting. AppModel republishes on
    /// `accessibilityDisplayOptionsDidChangeNotification` so SwiftUI re-reads it.
    @MainActor
    static var reduce: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The spring used everywhere — or a ≤200ms fade when Reduce Motion is on.
    @MainActor
    static func spring(_ response: Double, _ damping: Double) -> Animation {
        resolved(response: response, damping: damping, reduce: reduce)
    }

    /// Pure mapping (checkable without AppKit state): reduce → `.easeOut(0.18)`,
    /// otherwise the requested spring.
    static func resolved(response: Double, damping: Double, reduce: Bool) -> Animation {
        reduce
            ? .easeOut(duration: 0.18)
            : .spring(response: response, dampingFraction: damping)
    }
}
