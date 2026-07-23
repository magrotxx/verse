#if DEBUG
/// Converted from the planned Tests/VerseTests/TitleCleanerTests.swift —
/// same four test cases, same assertions, expressed via `check` (no XCTest
/// on this machine; see Checks.swift).
func runTitleCleanerChecks() {
    // testStripsFeatParenthetical
    check("stripsFeatParenthetical: (feat. Lola Young)") {
        TitleCleaner.clean("Like Him (feat. Lola Young)") == "Like Him"
    }
    check("stripsFeatParenthetical: (with Drake)") {
        TitleCleaner.clean("Sicko Mode (with Drake)") == "Sicko Mode"
    }
    check("stripsFeatParenthetical: [feat. Dido]") {
        TitleCleaner.clean("Stan [feat. Dido]") == "Stan"
    }

    // testStripsDashSuffixes
    check("stripsDashSuffixes: - Remastered 2009") {
        TitleCleaner.clean("Come Together - Remastered 2009") == "Come Together"
    }
    check("stripsDashSuffixes: - Single Version") {
        TitleCleaner.clean("Let It Be - Single Version") == "Let It Be"
    }

    // testLeavesCleanTitlesAlone
    check("leavesCleanTitlesAlone: WITHOUT ME") {
        TitleCleaner.clean("WITHOUT ME") == "WITHOUT ME"
    }
    check("leavesCleanTitlesAlone: Plain Song") {
        TitleCleaner.clean("Plain Song") == "Plain Song"
    }

    // testVariants
    check("variants: clean title -> [original]") {
        TitleCleaner.variants("Plain Song") == ["Plain Song"]
    }
    check("variants: feat title -> [original, cleaned]") {
        TitleCleaner.variants("Like Him (feat. Lola Young)")
            == ["Like Him (feat. Lola Young)", "Like Him"]
    }
}
#endif
