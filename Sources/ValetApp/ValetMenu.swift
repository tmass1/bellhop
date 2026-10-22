import AppKit
import ServiceManagement
import ValetCore

/// The Valet menu: every menu bar icon in a vertical list, tucked ones first, each with its real menu mirrored.
/// It opens with the last scan and refreshes in place once a new scan finishes.
@MainActor
final class ValetMenu: NSObject, NSMenuDelegate {
    private let engine: MenuBarEngine
    private let system: LiveAccessibility
    private let divider: DividerController
    private let keepers: KeeperController
    private let mirror: MenuMirror
    private let menu = NSMenu()
    private(set) var snapshot: MenuBarSnapshot?
    private weak var statusItem: NSStatusItem?
    /// Opens Arrange Menu Bar…
    var onArrange: (() -> Void)?
    /// Every new scan, for keepers and the Arrange window.
    var onScan: ((MenuBarSnapshot) -> Void)?

    init(
        engine: MenuBarEngine, system: LiveAccessibility, divider: DividerController, keepers: KeeperController,
        mirror: MenuMirror
    ) {
        self.engine = engine
        self.system = system
        self.divider = divider
        self.keepers = keepers
        self.mirror = mirror
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    func show(from item: NSStatusItem) {
        statusItem = item
        rebuild()
        item.menu = menu
        item.button?.performClick(nil)
    }

    /// Takes a scan made elsewhere (at launch), and passes it on like one of its own.
    func accept(_ fresh: MenuBarSnapshot) {
        snapshot = fresh
        onScan?(fresh)
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard system.isTrusted else { return }
        Task {
            let env = SystemSnapshot.capture()
            guard let fresh = try? await engine.scan(env) else { return }
            accept(fresh)
            rebuild()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach so the next click comes back through the button's action (⌥-click toggles arranging).
        statusItem?.menu = nil
    }

    // MARK: Building

    private func rebuild() {
        menu.removeAllItems()
        if !system.isTrusted {
            addOnboarding()
        } else if let snapshot {
            // Keepers are tucked icons shown again by Valet, so they're listed with the menu bar, in their order.
            let sections = MenuBarSections(snapshot)
            let byID = Dictionary(snapshot.icons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let keptIcons = keepers.kept.compactMap { byID[$0] }
            let tucked = sections.tucked.filter { !keepers.isKept($0.id) }
            menu.addItem(.sectionHeader(title: "Tucked Away"))
            if tucked.isEmpty {
                menu.addItem(disabled("Nothing tucked away"))
            }
            tucked.forEach { addIcon($0, keepable: true) }
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "In the Menu Bar"))
            keptIcons.forEach { addIcon($0, keepable: true) }
            sections.inBar.forEach { addIcon($0, keepable: false) }
        } else {
            menu.addItem(disabled("Reading the menu bar…"))
        }

        menu.addItem(.separator())
        let showTucked = NSMenuItem(title: "Show Tucked Icons", action: #selector(toggleArranging), keyEquivalent: "")
        showTucked.target = self
        showTucked.state = divider.arranging ? .on : .off
        showTucked.toolTip = "Or ⌥-click Valet."
        menu.addItem(showTucked)
        let arrange = NSMenuItem(title: "Arrange Menu Bar…", action: #selector(arrange), keyEquivalent: "")
        arrange.target = self
        menu.addItem(arrange)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Valet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Adds an icon's row and, for icons that can be kept, its ⌥ alternate.
    private func addIcon(_ icon: MenuBarIcon, keepable: Bool) {
        menu.addItem(iconItem(icon))
        if keepable { menu.addItem(keepItem(icon)) }
    }

    private func addOnboarding() {
        menu.addItem(disabled("Valet needs Accessibility access"))
        menu.addItem(disabled("It reads and presses menu bar items. Nothing else."))
        let open = NSMenuItem(
            title: "Open Privacy Settings…", action: #selector(openPrivacySettings), keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)
    }

    private func iconItem(_ icon: MenuBarIcon) -> NSMenuItem {
        let item = NSMenuItem(title: icon.name, action: nil, keyEquivalent: "")
        item.image = AppIcons.image(for: icon)
        if let status = icon.statusText {
            item.badge = NSMenuItemBadge(string: status)
        }
        if let submenu = mirror.menu(for: icon) {
            item.submenu = submenu
        } else {
            // No mirrored menu (a panel, or a menu only built when opened): pressing the icon opens it in place.
            mirror.pressesIcon(icon, item: item)
        }
        return item
    }

    /// Shown while ⌥ is held, in place of the icon's row: keep it in the menu bar, or tuck it away again.
    private func keepItem(_ icon: MenuBarIcon) -> NSMenuItem {
        let kept = keepers.isKept(icon.id)
        let item = NSMenuItem(
            title: kept ? "Tuck “\(icon.name)” Away" : "Keep “\(icon.name)” in Menu Bar",
            action: #selector(toggleKeep(_:)), keyEquivalent: ""
        )
        item.image = AppIcons.image(for: icon)
        item.target = self
        item.representedObject = icon.id
        item.isAlternate = true
        item.keyEquivalentModifierMask = .option
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Actions

    @objc private func toggleKeep(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        keepers.toggle(id, iconPosition: divider.iconPosition)
    }

    @objc private func arrange() {
        onArrange?()
    }

    @objc private func toggleArranging() {
        divider.toggleArranging()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            MenuMirror.alert("Couldn’t change Open at Login: \(error.localizedDescription)")
        }
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
