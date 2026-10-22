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
    private var keepers: KeeperController!
    private let arrange = ArrangeWindow()
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

        let mirror = MenuMirror(engine: engine)
        mirror.anchor = { [weak self] in
            guard let window = self?.statusItem.button?.window, let screen = window.screen else { return nil }
            return (Double(window.frame.minX), Double(screen.frame.maxX))
        }
        keepers = KeeperController(engine: engine, mirror: mirror)
        divider = DividerController(icon: statusItem, engine: engine)
        divider.leftmostItemMinX = { [weak keepers] in keepers?.leftmostMinX }
        keepers.onLayoutChange = { [weak divider] in divider?.resize() }
        keepers.onKeptChange = { [weak self] kept in self?.arrange.model.kept = kept }
        valetMenu = ValetMenu(engine: engine, system: system, divider: divider, keepers: keepers, mirror: mirror)
        valetMenu.onScan = { [weak self] snapshot in self?.accept(snapshot) }
        valetMenu.onArrange = { [weak self] in self?.showArrange() }
        arrange.model.onChange = { [weak self] kept in
            guard let self else { return }
            keepers.setKept(kept, iconPosition: divider.iconPosition)
        }
        divider.start()
        scanOnLaunch()
        startServer()
        // First-run onboarding: the system prompt adds Valet to the Accessibility list. The menu explains the rest.
        if !system.isTrusted { _ = LiveAccessibility.requestAccess() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    /// Keepers need the icons' names, status and menus, so read the menu bar once at launch.
    private func scanOnLaunch() {
        guard system.isTrusted else { return }
        Task {
            guard let snapshot = try? await engine.scan(SystemSnapshot.capture()) else { return }
            valetMenu.accept(snapshot)
        }
    }

    private func accept(_ snapshot: MenuBarSnapshot) {
        keepers.update(with: snapshot, iconPosition: divider.iconPosition)
        arrange.model.update(snapshot: snapshot, kept: keepers.kept)
    }

    private func showArrange() {
        if let snapshot = valetMenu.snapshot {
            arrange.model.update(snapshot: snapshot, kept: keepers.kept)
        }
        arrange.show()
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
