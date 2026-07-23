import Foundation

/// Normalizes player-reported track titles for LRCLIB lookups.
///
/// Streaming apps often report titles with noise LRCLIB doesn't index, e.g.
/// "Like Him (feat. Lola Young)" or "Come Together - Remastered 2009".
enum TitleCleaner {
    /// Strips "(feat. X)" / "[feat. X]" parentheticals and " - Remastered" /
    /// "- Single Version" style dash suffixes from `title` (case-insensitive),
    /// then trims whitespace. Returns `title` unchanged if cleaning would
    /// otherwise empty it.
    static func clean(_ title: String) -> String {
        var cleaned = title
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+-\s+(feat\.?|ft\.?|featuring|remaster|single version|radio edit|bonus track|deluxe|mono|stereo|live).*$"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }

    /// [original title, cleaned title] when cleaning changes it, else just `[original]`.
    static func variants(_ title: String) -> [String] {
        let cleaned = clean(title)
        return cleaned == title ? [title] : [title, cleaned]
    }
}
