import AppKit
import SwiftUI

/// A panel that can take clicks (the pill is interactive) but never steals key
/// focus from the user's real work.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the single full-screen transparent panel that hosts the floating pill.
/// The panel spans `screen.frame`; the pill is positioned *inside* the SwiftUI
/// hierarchy by `model.pillOrigin` (the window itself never moves), and
/// `PassThroughHostingView` lets every click outside the pill/popup shape fall
/// through to whatever app is behind it.
@MainActor
final class PillPanelController {
    private let panel: PillPanel
    private let model: AppModel
    private let layout = PillLayout()

    init(model: AppModel) {
        self.model = model
        let screen = Self.targetScreen()

        panel = PillPanel(
            contentRect: screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Shadows are drawn in SwiftUI on the pill/popup shapes, not by the
        // (full-screen, invisible) window.
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true

        let hosting = PassThroughHostingView(rootView: RootPillView(model: model))
        // hitTest delivers points in the hosting view's AppKit (bottom-left)
        // space, so the interactive shape must be returned in THAT space —
        // hence PillLayout.hitRect flips the panel-space rects. Weak captures
        // keep the panel → contentView → closure chain cycle-free.
        hosting.interactiveRect = { [weak self, weak model] in
            guard let self, let model, model.uiState != .hidden else { return .zero }
            return self.interactiveRect(for: model)
        }
        panel.contentView = hosting

        configureGeometry(for: screen)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.configureGeometry(for: PillPanelController.targetScreen()) }
        }
    }

    /// Panel = whole screen; pill width + visible-area clamp follow the screen.
    private func configureGeometry(for screen: NSScreen?) {
        guard let screen else { return }
        panel.setFrame(screen.frame, display: true)

        let visible = PillLayout.visibleRectInPanelSpace(screen: screen)
        model.pillVisibleRect = visible
        model.pillWidth = layout.pillMaxWidth(screen: screen)

        // Drop the pill at its default spot only the very first time; otherwise
        // keep the user's saved position and just re-clamp for the new geometry.
        if !model.hasStoredPillOrigin {
            model.pillOrigin = PillLayout.defaultOrigin(pillWidth: model.pillWidth, visible: visible)
        }
        model.clampPillOrigin(to: visible)
    }

    /// Interactive shape in AppKit (bottom-left) hosting-view coordinates.
    private func interactiveRect(for model: AppModel) -> CGRect {
        let panelHeight = panel.frame.height
        let pillRect = PillLayout.hitRect(
            topLeft: model.pillOrigin,
            size: CGSize(width: model.pillWidth, height: layout.pillHeight),
            panelHeight: panelHeight
        )
        switch model.uiState {
        case .hidden:
            return .zero
        case .pill:
            return pillRect
        case .popup:
            let popup = layout.popupRect(
                pillOrigin: model.pillOrigin,
                pillWidth: model.pillWidth,
                visible: model.pillVisibleRect
            )
            let popupRect = PillLayout.hitRect(
                topLeft: popup.origin, size: popup.size, panelHeight: panelHeight
            )
            return pillRect.union(popupRect)
        }
    }

    /// The screen the pill lives on: the one with the active menu bar, else the
    /// first attached display.
    static func targetScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }
}
