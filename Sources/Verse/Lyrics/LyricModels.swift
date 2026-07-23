import Foundation

struct WordTiming: Equatable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    /// True when this word falls inside a bracketed span, e.g. the "(ooh)"
    /// in "run away (ooh) tonight" — an inline ad-lib/background echo.
    var isEcho: Bool = false
}

struct LyricLine: Equatable, Identifiable {
    let id: Int
    let start: TimeInterval
    var end: TimeInterval
    let text: String
    /// Word-level timings. Real (from enhanced LRC) when available,
    /// otherwise synthesized: distributed across the line's duration,
    /// weighted by word length — always present for non-empty lines,
    /// so no theme is ever disabled by missing word data.
    var words: [WordTiming]
    /// True when the trimmed line text is entirely wrapped by `(…)` or
    /// `[…]` — a whole-line echo/ad-lib, e.g. "(ooh, la la)".
    var isEcho: Bool = false

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// A display unit for the compact wing: either a whole line, or one piece
/// of a long line broken at word boundaries. Each chunk carries its own
/// time window and word timings, so every theme animates per-chunk.
struct LyricChunk: Equatable, Identifiable {
    let id: String // "lineIndex-chunkIndex"
    let lineIndex: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let words: [WordTiming]
}

enum LyricsContent {
    case synced(LyricsTimeline)
    case plain(String)     // unsynced lyrics: static display, no animation
    case instrumental
    case none              // no lyrics found: show track title in the wing
}

/// The synced-lyrics engine: answers "what line/word/chunk is active at time t".
struct LyricsTimeline {
    let lines: [LyricLine]

    /// Index of the active line at time `t`, or nil before the first line.
    func lineIndex(at t: TimeInterval) -> Int? {
        if lines.isEmpty || t < lines[0].start { return nil }
        // Binary search for the last line whose start <= t.
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].start <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// True in the gap before the first line or inside an empty timed line —
    /// i.e. an instrumental break where no stale text should show.
    func isInstrumentalBreak(at t: TimeInterval) -> Bool {
        guard let i = lineIndex(at: t) else { return true }
        return lines[i].isEmpty
    }

    /// Time of the next line start after `t` (for break countdowns).
    func nextLineStart(after t: TimeInterval) -> TimeInterval? {
        lines.first(where: { $0.start > t && !$0.isEmpty })?.start
    }

    // MARK: - Synthesized word timings

    /// Distribute word timings across [start, end], weighted by word length.
    /// Used when the LRC has line-level timestamps only.
    static func synthesizeWords(text: String, start: TimeInterval, end: TimeInterval) -> [WordTiming] {
        let tokens = text.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let duration = max(end - start, 0.3)
        // Weight = character count + 1 so tiny words still get a beat.
        let weights = tokens.map { Double($0.count + 1) }
        let total = weights.reduce(0, +)
        let echoFlags = markEcho(tokens)
        var cursor = start
        var result: [WordTiming] = []
        for i in tokens.indices {
            let span = duration * (weights[i] / total)
            result.append(WordTiming(text: tokens[i], start: cursor, end: cursor + span, isEcho: echoFlags[i]))
            cursor += span
        }
        return result
    }

    // MARK: - Echo detection

    /// Bracket-depth tracker shared by `synthesizeWords` and `LRCParser`'s
    /// enhanced word-level path. A token beginning with `(`/`[` raises depth
    /// before flagging (the opening token itself is inside the span); a
    /// token ending with `)`/`]` lowers depth after (the closing token is
    /// still flagged). A token is echo when depth > 0 at its position.
    static func markEcho(_ tokens: [String]) -> [Bool] {
        var depth = 0
        var flags: [Bool] = []
        flags.reserveCapacity(tokens.count)
        for token in tokens {
            if token.hasPrefix("(") || token.hasPrefix("[") { depth += 1 }
            flags.append(depth > 0)
            if token.hasSuffix(")") || token.hasSuffix("]") { depth = max(0, depth - 1) }
        }
        return flags
    }
}
