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

    // Apple Music-style bg-vocal merging (2026-07-25)
    check("mergeEchoLines: adjacent bg vocal merges inline into the main line") {
        let t = LRCParser.parse(
            "[00:10.00]This is what you get\n[00:13.00](aaah ooh yeah)\n[00:16.00]Next line")!
        return t.lines.count == 2
            && t.lines[0].text == "This is what you get (aaah ooh yeah)"
            && !t.lines[0].isEcho
            && t.lines[0].words.suffix(3).allSatisfy(\.isEcho)
            && t.lines[0].words.prefix(5).allSatisfy { !$0.isEcho }
            && t.lines.enumerated().allSatisfy { $0.offset == $0.element.id }
    }
    check("mergeEchoLines: distant echo stays a standalone echo line") {
        let t = LRCParser.parse("[00:10.00]Main line here\n[00:25.00](oooh)")!
        return t.lines.count == 2 && t.lines[1].isEcho
    }
    check("mergeEchoLines: leading echo with no main line stays standalone") {
        let t = LRCParser.parse("[00:02.00](oooh)\n[00:06.00]First real line")!
        return t.lines.count == 2 && t.lines[0].isEcho && !t.lines[1].isEcho
    }

    // Trailing punctuation after a close must not defeat depth tracking
    // (the "grow wings" bug: "(One day...), I am gonna grow wings" flagged
    // the entire rest of the line as echo).
    check("markEcho: close followed by punctuation ends the span") {
        let words = LyricsTimeline.synthesizeWords(
            text: "(One day...), I am gonna grow wings", start: 0, end: 5)
        return words.map(\.isEcho) == [true, true, false, false, false, false, false]
    }
}
#endif
