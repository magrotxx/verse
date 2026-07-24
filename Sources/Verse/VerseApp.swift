import AppKit

@main
enum VerseMain {
    @MainActor
    static func main() {
        #if DEBUG
        VerseChecks.runIfRequested() // exits here when launched with --checks
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate // NSApplication.delegate is unowned(unsafe);
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { // keep it alive for the app's lifetime
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panelController: PillPanelController!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model

        statusItemController = StatusItemController(model: model)
        panelController = PillPanelController(model: model)

        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }
}
