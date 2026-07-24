#if DEBUG
import AppKit

/// Verifies `PillDisplay.at` — the pure pill content state machine (title /
/// chunk / echo / dots / blank) and its instrumental-gap thresholds. This is
/// the on-screen behavior the headless `--checks` run can still pin down.
func runPillContentChecks() {
    // Timeline: line 0 sings, line 1 is a whole-line echo "(ooh)", line 2 is
    // far away leaving a 17s instrumental gap (3s → 20s).
    let a = LyricChunk(id: "0-0", lineIndex: 0, start: 1, end: 2, text: "hello world",
                       words: LyricsTimeline.synthesizeWords(text: "hello world", start: 1, end: 2))
    let b = LyricChunk(id: "1-0", lineIndex: 1, start: 2, end: 3, text: "(ooh)",
                       words: LyricsTimeline.synthesizeWords(text: "(ooh)", start: 2, end: 3))
    let c = LyricChunk(id: "2-0", lineIndex: 2, start: 20, end: 21, text: "back again",
                       words: LyricsTimeline.synthesizeWords(text: "back again", start: 20, end: 21))
    let lines = [
        LyricLine(id: 0, start: 1, end: 2, text: "hello world", words: [], isEcho: false),
        LyricLine(id: 1, start: 2, end: 3, text: "(ooh)", words: [], isEcho: true),
        LyricLine(id: 2, start: 20, end: 21, text: "back again", words: [], isEcho: false),
    ]
    let content = LyricsContent.synced(LyricsTimeline(lines: lines))
    let chunks = [a, b, c]

    check("PillDisplay: before the first line shows the title") {
        PillDisplay.at(t: 0.5, content: content, chunks: chunks, duration: 25) == .title
    }
    check("PillDisplay: inside a sung chunk shows that chunk") {
        PillDisplay.at(t: 1.5, content: content, chunks: chunks, duration: 25) == .chunk(a)
    }
    check("PillDisplay: a bracketed line renders as an echo") {
        PillDisplay.at(t: 2.5, content: content, chunks: chunks, duration: 25) == .echo(b)
    }
    check("PillDisplay: a >15s gap contracts to tiny dots") {
        PillDisplay.at(t: 10, content: content, chunks: chunks, duration: 25) == .dots(tiny: true)
    }

    // 5s gap (2 → 7): dots, not tiny.
    let midGap = [a, LyricChunk(id: "9-0", lineIndex: 9, start: 7, end: 8, text: "later",
                                words: LyricsTimeline.synthesizeWords(text: "later", start: 7, end: 8))]
    check("PillDisplay: a 3–15s gap shows (non-tiny) dots") {
        PillDisplay.at(t: 4, content: LyricsContent.synced(LyricsTimeline(lines: lines)),
                       chunks: midGap, duration: 25) == .dots(tiny: false)
    }

    // 1.5s gap (2 → 3.5): blank, not dots.
    let shortGap = [a, LyricChunk(id: "8-0", lineIndex: 8, start: 3.5, end: 4.5, text: "soon",
                                  words: LyricsTimeline.synthesizeWords(text: "soon", start: 3.5, end: 4.5))]
    check("PillDisplay: a <3s inter-line gap is blank") {
        PillDisplay.at(t: 2.7, content: LyricsContent.synced(LyricsTimeline(lines: lines)),
                       chunks: shortGap, duration: 25) == .blank
    }

    check("PillDisplay: no lyrics / plain lyrics fall back to the title") {
        PillDisplay.at(t: 5, content: .none, chunks: [], duration: 25) == .title
            && PillDisplay.at(t: 5, content: .plain("x"), chunks: [], duration: 25) == .title
    }
    check("PillDisplay: a fully instrumental track shows dots") {
        PillDisplay.at(t: 5, content: .instrumental, chunks: [], duration: 25) == .dots(tiny: false)
    }

    // Echo detection: whole-line flag path (words not bracketed, line is).
    check("PillDisplay.isEcho: falls back to the backing line's echo flag") {
        let plainWords = LyricChunk(id: "1-1", lineIndex: 1, start: 2, end: 3, text: "no brackets",
                                    words: LyricsTimeline.synthesizeWords(text: "no brackets", start: 2, end: 3))
        return PillDisplay.isEcho(plainWords, lines: lines) == true   // line 1 isEcho = true
            && PillDisplay.isEcho(a, lines: lines) == false           // line 0 isEcho = false
    }
}
#endif
