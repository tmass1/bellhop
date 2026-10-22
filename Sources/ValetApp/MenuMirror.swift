import AppKit
import ValetCore

/// Builds native copies of other apps' menus and runs what's chosen in them. Shared by the Valet menu and keepers.
@MainActor
final class MenuMirror: NSObject {
    private let engine: MenuBarEngine
    /// Where panels opened from the Valet menu should go: the left edge of Valet's icon, and its screen's right edge.
    var anchor: (() -> (x: Double, screenMaxX: Double)?)?

    init(engine: MenuBarEngine) {
        self.engine = engine
    }

    /// The icon's real menu as an `NSMenu`, or nil when Valet has none mirrored (panels, and menus that only
    /// exist while open).
    func menu(for icon: MenuBarIcon) -> NSMenu? {
        guard let entries = icon.menu, !entries.isEmpty else { return nil }
        let menu = NSMenu(title: icon.name)
        menu.autoenablesItems = false
        entries.forEach { menu.addItem(entryItem($0, path: [icon.name])) }
        return menu
    }

    /// Makes `item` open the real icon when chosen. A panel it opens is moved under Valet's icon, since the real
    /// icon may be tucked behind the notch.
    func pressesIcon(_ icon: MenuBarIcon, item: NSMenuItem) {
        item.action = #selector(openIcon(_:))
        item.target = self
        item.representedObject = icon.name
    }

    @objc private func openIcon(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        guard let anchor = anchor?() else { return run(name, confirm: false) }
        Task {
            do {
                _ = try await engine.open(
                    name, alignTo: anchor.x, screenMaxX: anchor.screenMaxX, env: SystemSnapshot.capture()
                )
            } catch let error as ValetError {
                Self.alert(error.message)
            } catch {
                Self.alert(error.localizedDescription)
            }
        }
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
            item.action = #selector(runPath(_:))
            item.target = self
            item.representedObject = MenuPaths.join(path + [title])
        }
        return item
    }

    @objc private func runPath(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        run(path, confirm: false)
    }

    func run(_ path: String, confirm: Bool) {
        Task {
            do {
                _ = try await engine.run(path, confirm: confirm, env: SystemSnapshot.capture())
            } catch ValetError.needsConfirmation(let path) {
                if confirmDestructive(path) { run(path, confirm: true) }
            } catch let error as ValetError {
                Self.alert(error.message)
            } catch {
                Self.alert(error.localizedDescription)
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

    static func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        NSApp.activate()
        alert.runModal()
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
