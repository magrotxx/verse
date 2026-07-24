import AppKit
import SwiftUI

/// A panel that can take clicks (the pill is interactive) but never steals key
/// focus from the user's real work.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that passes clicks through everywhere except the current visible
/// shape (pill or popup), so the transparent rest of the full-screen panel never
/// blocks the apps behind it.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    /// Interactive shape in this view's AppKit (bottom-left) coordinates.
    var interactiveRect: @MainActor () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = superview.map { convert(point, from: $0) } ?? point
        guard interactiveRect().contains(p) else { return nil }
        return super.hitTest(point)
    }

    /// First click should act even when the panel isn't key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the single full-screen transparent panel that hosts the floating pill.
/// The panel spans `screen.frame`; the pill/popup are positioned *inside* the
/// SwiftUI hierarchy by `model.pillAnchor` (the window itself never moves), and
/// `PassThroughHostingView` lets every click outside the visible shape fall
/// through to whatever app is behind it.
@MainActor
final class PillPanelController {
    private let panel: PillPanel
    private let model: AppModel
    private let layout = PillLayout()

    private var escMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var scrollMonitor: Any?

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
        panel.hasShadow = false          // shadows drawn in SwiftUI on the shapes
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true

        let hosting = PassThroughHostingView(rootView: RootPillView(model: model))
        hosting.interactiveRect = { [weak self, weak model] in
            guard let self, let model else { return .zero }
            return self.interactiveRect(for: model)
        }
        panel.contentView = hosting

        configureGeometry(for: screen)
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.configureGeometry(for: PillPanelController.targetScreen()) }
        }
    }

    deinit {
        for m in [escMonitor, localMouseMonitor, globalMouseMonitor, scrollMonitor] {
            if let m { NSEvent.removeMonitor(m) }
        }
    }

    // MARK: - Geometry

    /// Panel = whole screen; max pill width + visible-area clamp follow the
    /// screen. The pill's ACTUAL width is dynamic (model-owned, revision A).
    private func configureGeometry(for screen: NSScreen?) {
        guard let screen else { return }
        panel.setFrame(screen.frame, display: true)

        let visible = PillLayout.visibleRectInPanelSpace(screen: screen)
        model.pillVisibleRect = visible
        model.pillMaxWidth = layout.pillMaxWidth(screen: screen)

        if !model.hasStoredPillAnchor {
            if model.isFirstRunDemo {
                // First-run moment: the demo pill appears center-screen and
                // settles wherever the user drops it.
                model.pillAnchorMode = .center
                model.pillAnchor = CGPoint(
                    x: visible.midX, y: visible.midY - layout.pillHeight / 2
                )
            } else {
                let placement = PillLayout.defaultAnchor(visible: visible)
                model.pillAnchorMode = placement.mode
                model.pillAnchor = placement.anchor
            }
        }
        model.clampPillAnchor()
    }

    /// The pill's current frame in panel space, derived from anchor/mode/width.
    private func pillPanelFrame() -> CGRect {
        layout.pillFrame(
            anchor: model.pillAnchor, mode: model.pillAnchorMode, width: model.pillWidth
        )
    }

    /// Interactive shape in AppKit (bottom-left) hosting-view coordinates.
    /// The pill (or idle ball) is always present — revision A removed `.hidden`.
    private func interactiveRect(for model: AppModel) -> CGRect {
        let frame = pillPanelFrame()
        let pillRect = PillLayout.hitRect(
            topLeft: frame.origin, size: frame.size, panelHeight: panel.frame.height
        )
        switch model.uiState {
        case .pill:
            return pillRect
        case .popup:
            return pillRect.union(popupHitRect())
        }
    }

    /// Popup rect in AppKit (bottom-left) hosting-view coordinates.
    private func popupHitRect() -> CGRect {
        let popup = layout.popupRect(pillFrame: pillPanelFrame(), visible: model.pillVisibleRect)
        return PillLayout.hitRect(topLeft: popup.origin, size: popup.size, panelHeight: panel.frame.height)
    }

    /// Popup rect in SCREEN coordinates (for hit-testing raw mouse events).
    private func popupScreenRect() -> CGRect {
        popupHitRect().offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    // MARK: - Dismissal / browse monitors (pattern: the old scroll monitor)

    private func installMonitors() {
        // Esc collapses the popup (even when pinned — it is an explicit dismiss).
        // `MainActor.assumeIsolated` returns Void (returning the non-Sendable
        // NSEvent out of it would cross an isolation boundary); the swallow
        // decision travels back via a Sendable Bool.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isEsc = event.keyCode == 53
            var swallow = false
            MainActor.assumeIsolated {
                guard let self, self.model.uiState == .popup, isEsc else { return }
                self.collapse()
                swallow = true
            }
            return swallow ? nil : event
        }

        // Click outside the popup collapses it, unless pinned. Local monitor
        // handles clicks that land on our panel (e.g. the pill region beside
        // the popup); the global monitor handles clicks on other apps.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.collapseIfClickOutsidePopup() }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapseIfClickOutsidePopup() }
        }

        // Scroll inside the popup → browse the full lyrics list.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let onPanel = event.window is PillPanel
            MainActor.assumeIsolated {
                guard let self, self.model.uiState == .popup, onPanel else { return }
                if self.model.browsing { self.model.restartBrowseTimer() }
                else { self.model.enterBrowse() }
            }
            return event
        }
    }

    private func collapseIfClickOutsidePopup() {
        guard model.uiState == .popup, !model.pinned else { return }
        if !popupScreenRect().contains(NSEvent.mouseLocation) { collapse() }
    }

    /// Exhale back into the pill (the spring lives on RootPillView's uiState).
    private func collapse() {
        model.uiState = .pill
        model.exitBrowse()
    }

    /// The screen the pill lives on: the one with the active menu bar, else the
    /// first attached display.
    static func targetScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }
}
