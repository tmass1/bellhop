import AppKit
import ValetCore

/// Valet's status item, its menu, the divider, and the socket the `valet` CLI talks to.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let system = LiveAccessibility()
    private lazy var engine = MenuBarEngine(system: system)
    private var statusItem: NSStatusItem!
    private var valetMenu: ValetMenu!
    private var divider: DividerController!
    private var server: SocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DividerController.placeIconOnFirstRun()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = DividerController.iconName
        if let button = statusItem.button {
            // Template image from Valet-Icon-Assets: AppKit tints it for light, dark and selected states. Always 18 pt.
            if let image = Bundle.main.image(forResource: "ValetMenuTemplate") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = "Valet · ⌥-click to show tucked icons"
            button.setAccessibilityLabel("Valet")
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        divider = DividerController(icon: statusItem, engine: engine)
        valetMenu = ValetMenu(engine: engine, system: system, divider: divider)
        divider.start()
        startServer()
        // First-run onboarding: the system prompt adds Valet to the Accessibility list. The menu explains the rest.
        if !system.isTrusted { _ = LiveAccessibility.requestAccess() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    @objc private func iconClicked() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            divider.toggleArranging()
        } else {
            valetMenu.show(from: statusItem)
        }
    }

    private func startServer() {
        let system = system
        let handler = RequestHandler(
            engine: engine,
            capture: { await MainActor.run { SystemSnapshot.capture() } },
            status: { StatusInfo(version: ValetCore.version, trusted: system.isTrusted, pid: getpid()) }
        )
        let server = SocketServer(path: IPC.socketPath) { await handler.handle($0) }
        do {
            try server.start()
            self.server = server
        } catch {
            NSLog("Valet: couldn't start the CLI socket: \(error)")
        }
    }
}
