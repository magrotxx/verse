#if DEBUG
/// Converted from the planned Tests/VerseTests/EchoDetectionTests.swift —
/// same four test cases, same assertions, expressed via `check` (no XCTest
/// on this machine; see Checks.swift).
func runEchoDetectionChecks() {
    // testWholeLineEcho
    check("wholeLineEcho: parenthetical line isEcho true") {
        let t = LRCParser.parse("[00:10.00](ooh, la la)\n[00:14.00]Real line here")!
        return t.lines[0].isEcho
    }
    check("wholeLineEcho: real line isEcho false") {
        let t = LRCParser.parse("[00:10.00](ooh, la la)\n[00:14.00]Real line here")!
        return !t.lines[1].isEcho
    }

    // testSquareBracketEcho
    check("squareBracketEcho: [background hum] isEcho true") {
        let t = LRCParser.parse("[00:10.00][background hum]\n[00:12.00]Words")!
        return t.lines[0].isEcho
    }

    // testInlineEchoWords
    check("inlineEchoWords: run away (ooh) tonight") {
        let words = LyricsTimeline.synthesizeWords(text: "run away (ooh) tonight", start: 0, end: 4)
        return words.map(\.isEcho) == [false, false, true, false]
    }

    // testNoBracketsNoEcho
    check("noBracketsNoEcho: plain words only") {
        let words = LyricsTimeline.synthesizeWords(text: "plain words only", start: 0, end: 2)
        return words.allSatisfy { !$0.isEcho }
    }
}
#endif
