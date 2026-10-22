import AppKit
import ValetCore

/// Valet's status item, its menu, the divider, and the socket the `valet` CLI talks to.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let system = LiveAccessibility()
    private lazy var engine = MenuBarEngine(system: system)
    private var statusItem: NSStatusItem!
    private var valetPanel: ValetPanelController!
    private var divider: DividerController!
    private var keepers: KeeperController!
    private var palette: PaletteController!
    private let settings = SettingsWindow()
    private var server: SocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.apply()
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
        keepers.onKeptChange = { [weak self] _ in self?.valetPanel.keptChanged() }
        valetPanel = ValetPanelController(
            engine: engine, system: system, keepers: keepers, mirror: mirror, divider: divider
        )
        valetPanel.onScan = { [weak self] snapshot in self?.accept(snapshot) }
        valetPanel.openOnHover(statusItem)
        palette = PaletteController(engine: engine, system: system, mirror: mirror) { [weak keepers] in
            keepers?.kept ?? []
        }
        palette.anchor = mirror.anchor
        valetPanel.model.onSearch = { [weak self] in
            self?.valetPanel.close()
            self?.palette.show()
        }
        valetPanel.model.onSettings = { [weak self] in
            self?.valetPanel.close()
            self?.settings.show()
        }
        palette.onScan = { [weak self] snapshot in
            self?.valetPanel.receive(snapshot)
            self?.accept(snapshot)
        }
        SystemSnapshot.dividerFrames = { [weak divider] in divider?.tuckingFrames ?? [] }
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
            valetPanel.accept(snapshot)
        }
    }

    /// Every scan, wherever it was made, reaches keepers and the palette.
    private func accept(_ snapshot: MenuBarSnapshot) {
        keepers.update(with: snapshot, iconPosition: divider.iconPosition)
        palette.accept(snapshot)
    }

    @objc private func iconClicked() {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            divider.toggleArranging()
        } else {
            valetPanel.toggle(from: statusItem)
        }
    }

    private func startServer() {
        let system = system
        let palette = palette!
        let keepers = keepers!
        let divider = divider!
        let handler = RequestHandler(
            engine: engine,
            capture: { await MainActor.run { SystemSnapshot.capture() } },
            status: { StatusInfo(version: ValetCore.version, trusted: system.isTrusted, pid: getpid()) },
            showPalette: { query in await MainActor.run { palette.show(query: query) } },
            keep: { icon, shouldKeep in
                await MainActor.run {
                    let others = keepers.kept.filter { $0 != icon.id }
                    keepers.setKept(shouldKeep ? others + [icon.id] : others, iconPosition: divider.iconPosition)
                    return keepers.kept
                }
            }
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
