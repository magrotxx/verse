#if DEBUG
import AppKit

/// Converted from the planned Tests/VerseTests/FittedFontTests.swift —
/// same three test cases, same assertions, expressed via `check` (no XCTest
/// on this machine; see Checks.swift).
func runFittedFontChecks() {
    // testShortTextKeepsBaseSize
    check("shortTextKeepsBaseSize: \"Hi\" stays at base size") {
        FittedFont.pointSize(text: "Hi", base: 21, weight: .semibold,
                              design: .serif, maxWidth: 400) == 21
    }

    // testLongTextShrinks
    check("longTextShrinks: shrinks below base") {
        let long = String(repeating: "supercalifragilistic ", count: 6)
        let s = FittedFont.pointSize(text: long, base: 21, weight: .semibold,
                                      design: .serif, maxWidth: 400)
        return s < 21
    }
    check("longTextShrinks: floor still respected") {
        let long = String(repeating: "supercalifragilistic ", count: 6)
        let s = FittedFont.pointSize(text: long, base: 21, weight: .semibold,
                                      design: .serif, maxWidth: 400)
        return s >= 21 * 0.6
    }

    // testFloorHolds
    check("floorHolds: absurd text clamps to exactly the floor") {
        let absurd = String(repeating: "wordswordswords ", count: 60)
        let s = FittedFont.pointSize(text: absurd, base: 20, weight: .semibold,
                                      design: .serif, maxWidth: 300, floorFactor: 0.6)
        return abs(s - 12) <= 0.01
    }
}
#endif
