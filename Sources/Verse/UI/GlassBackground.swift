import SwiftUI
import AppKit

/// Behind-window vibrancy (`NSVisualEffectView`) for the pill + popup glass.
/// Blurs whatever app is behind the transparent panel; callers composite the
/// album-hue wash on top and clip to their own shape (capsule / rounded rect).
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow   // blur content behind the window
        view.state = .active                // stay vibrant even when not key
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
