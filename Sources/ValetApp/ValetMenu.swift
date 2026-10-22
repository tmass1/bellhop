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
    private let menu = NSMenu()
    private var snapshot: MenuBarSnapshot?
    private weak var statusItem: NSStatusItem?

    init(engine: MenuBarEngine, system: LiveAccessibility, divider: DividerController) {
        self.engine = engine
        self.system = system
        self.divider = divider
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

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard system.isTrusted else { return }
        Task {
            let env = SystemSnapshot.capture()
            guard let fresh = try? await engine.scan(env) else { return }
            snapshot = fresh
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
            let sections = MenuBarSections(snapshot)
            menu.addItem(.sectionHeader(title: "Tucked Away"))
            if sections.tucked.isEmpty {
                menu.addItem(disabled("Nothing tucked away"))
            }
            sections.tucked.forEach { menu.addItem(iconItem($0)) }
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "In the Menu Bar"))
            sections.inBar.forEach { menu.addItem(iconItem($0)) }
        } else {
            menu.addItem(disabled("Reading the menu bar…"))
        }

        menu.addItem(.separator())
        let showTucked = NSMenuItem(title: "Show Tucked Icons", action: #selector(toggleArranging), keyEquivalent: "")
        showTucked.target = self
        showTucked.state = divider.arranging ? .on : .off
        showTucked.toolTip = "Or ⌥-click Valet. ⌘-drag Valet’s icon to choose what stays in the menu bar."
        menu.addItem(showTucked)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Valet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        if let status = icon.title, status != icon.name, status.count <= 24 {
            item.badge = NSMenuItemBadge(string: status)
        }
        if let entries = icon.menu, !entries.isEmpty {
            let submenu = NSMenu(title: icon.name)
            submenu.autoenablesItems = false
            entries.forEach { submenu.addItem(entryItem($0, path: [icon.name])) }
            item.submenu = submenu
        } else {
            // No mirrored menu (a panel, or a menu only built when opened): pressing the icon opens it in place.
            item.action = #selector(pressIcon(_:))
            item.target = self
            item.representedObject = icon.name
        }
        return item
    }

    private func entryItem(_ entry: MenuEntry, path: [String]) -> NSMenuItem {
        guard !entry.isSeparator, let title = entry.title else { return .separator() }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = entry.enabled
        item.state = entry.mark == nil ? .off : .on
        if let shortcut = entry.shortcut { Shortcut.apply(shortcut, to: item) }
        if let children = entry.children {
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            children.forEach { submenu.addItem(entryItem($0, path: path + [title])) }
            item.submenu = submenu
        } else {
            item.action = #selector(runEntry(_:))
            item.target = self
            item.representedObject = MenuPaths.join(path + [title])
        }
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Actions

    @objc private func runEntry(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        run(path, confirm: false)
    }

    @objc private func pressIcon(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        run(name, confirm: false)
    }

    private func run(_ path: String, confirm: Bool) {
        Task {
            do {
                _ = try await engine.run(path, confirm: confirm, env: SystemSnapshot.capture())
            } catch ValetError.needsConfirmation(let path) {
                if confirmDestructive(path) { run(path, confirm: true) }
            } catch let error as ValetError {
                alert(error.message)
            } catch {
                alert(error.localizedDescription)
            }
        }
    }

    /// Quit, Delete, Sign Out and Reset ask first, so a stray click can't quit something.
    private func confirmDestructive(_ path: String) -> Bool {
        let title = MenuPaths.parse(path).last ?? path
        let alert = NSAlert()
        alert.messageText = "\(title)?"
        alert.informativeText = "\(path) can’t be undone."
        alert.addButton(withTitle: title.split(separator: " ").first.map(String.init) ?? "Run")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        NSApp.activate()
        alert.runModal()
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
            alert("Couldn’t change Open at Login: \(error.localizedDescription)")
        }
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Turns a menu's shortcut string ("⌃⌥⇧⌘K") into a key equivalent, so the mirrored item shows it the native way.
enum Shortcut {
    static func apply(_ shortcut: String, to item: NSMenuItem) {
        guard let key = shortcut.last else { return }
        var mask: NSEvent.ModifierFlags = []
        if shortcut.contains("⌃") { mask.insert(.control) }
        if shortcut.contains("⌥") { mask.insert(.option) }
        if shortcut.contains("⇧") { mask.insert(.shift) }
        if shortcut.contains("⌘") { mask.insert(.command) }
        item.keyEquivalent = String(key).lowercased()
        item.keyEquivalentModifierMask = mask
    }
}
