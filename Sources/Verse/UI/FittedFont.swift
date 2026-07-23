import AppKit

/// Computes a point size that shrinks `base` just enough for `text` to fit
/// within `maxWidth`, clamped so it never shrinks past `floorFactor` of
/// `base`. Lets a popup/vibe-mode current line scale down uniformly instead
/// of truncating or wrapping.
///
/// Callers may invoke this once per animation frame (target 120Hz), so
/// results are cached.
enum FittedFont {
    /// Keyed by every input that affects the returned size, since any of
    /// them changes the measured natural width or the clamp bounds.
    private static let cache = NSCache<NSString, NSNumber>()

    static func pointSize(
        text: String,
        base: CGFloat,
        weight: NSFont.Weight,
        design: NSFontDescriptor.SystemDesign,
        maxWidth: CGFloat,
        floorFactor: CGFloat = 0.6
    ) -> CGFloat {
        let key = "\(text)|\(base)|\(maxWidth)|\(weight.rawValue)|\(design.rawValue)|\(floorFactor)" as NSString
        if let cached = cache.object(forKey: key) {
            return CGFloat(cached.doubleValue)
        }

        let font = styledFont(base: base, weight: weight, design: design)
        let naturalWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let ratio = min(max(maxWidth / naturalWidth, floorFactor), 1.0)
        let size = base * ratio

        cache.setObject(NSNumber(value: Double(size)), forKey: key)
        return size
    }

    /// Builds the NSFont used for measurement: system font at `base`/`weight`
    /// with `design` applied, falling back to the plain system font if the
    /// descriptor can't resolve that design (e.g. unavailable on this OS).
    private static func styledFont(
        base: CGFloat,
        weight: NSFont.Weight,
        design: NSFontDescriptor.SystemDesign
    ) -> NSFont {
        let systemFont = NSFont.systemFont(ofSize: base, weight: weight)
        guard let designed = systemFont.fontDescriptor.withDesign(design),
              let designedFont = NSFont(descriptor: designed, size: base)
        else {
            return systemFont
        }
        return designedFont
    }
}
