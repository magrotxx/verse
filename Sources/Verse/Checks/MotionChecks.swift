#if DEBUG
import SwiftUI

/// Verifies the pure Reduce Motion mapping: every spring in the app resolves
/// through `Motion.resolved`, so this pins the accessibility behavior the
/// headless runner can't toggle system-wide.
func runMotionChecks() {
    check("Motion: reduce=true turns any spring into the 0.18s fade") {
        Motion.resolved(response: 0.45, damping: 0.85, reduce: true)
            == Animation.easeOut(duration: 0.18)
    }
    check("Motion: reduce=false keeps the requested spring") {
        Motion.resolved(response: 0.45, damping: 0.85, reduce: false)
            == Animation.spring(response: 0.45, dampingFraction: 0.85)
    }
    check("Motion: distinct springs stay distinct when not reduced") {
        Motion.resolved(response: 0.3, damping: 0.5, reduce: false)
            != Motion.resolved(response: 0.45, damping: 0.85, reduce: false)
    }
}
#endif
