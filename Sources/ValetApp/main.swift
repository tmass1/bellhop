import AppKit
import ValetCore

// Status item plus the socket the `valet` CLI talks to. The real menu and palette wait for approved mocks
// (milestones 3 and 4).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var server: SocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Template image from Valet-Icon-Assets: AppKit tints it for light, dark and selected states. Always 18 pt.
        if let image = Bundle.main.image(forResource: "ValetMenuTemplate") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            item.button?.image = image
        }
        item.button?.toolTip = "Valet"
        item.button?.setAccessibilityLabel("Valet")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Valet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        // Placeholder for milestone 3's onboarding: shows the system prompt the first time.
        _ = LiveAccessibility.requestAccess()
        startServer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func startServer() {
        let system = LiveAccessibility()
        let handler = RequestHandler(
            engine: MenuBarEngine(system: system),
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
