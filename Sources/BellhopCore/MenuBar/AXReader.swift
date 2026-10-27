import CoreGraphics
import Foundation

/// Stateless reads over Accessibility elements, shared by `MenuBarEngine`'s scan, menu and run paths.
/// Only call it from inside the engine's actor.
struct AXReader {
    var maxDepth = 6
    var maxMenuItems = 2000

    static let iconAttributes = [
        AXName.title, AXName.description, AXName.help, AXName.role, AXName.subrole,
        AXName.position, AXName.size, AXName.children,
    ]
    static let menuItemAttributes = [
        AXName.title, AXName.enabled, AXName.markChar, AXName.cmdChar, AXName.cmdModifiers, AXName.children,
    ]

    struct FoundIcon {
        var app: RunningApp
        var element: any AXElement
        var role: String?
        var title: String?
        var description: String?
        var help: String?
        var frame: Frame?
        var actions: [String]
        var menuElement: (any AXElement)?
    }

    func read(_ element: any AXElement, app: RunningApp) -> FoundIcon {
        let outer = element.attributes(Self.iconAttributes)
        var frame: Frame?
        if let origin = outer[AXName.position]?.point, let size = outer[AXName.size]?.size {
            frame = Frame(CGRect(origin: origin, size: size))
        }
        // macOS 27's MenuBarAgent wraps each system item in an AXGroup; the real item is its child. Keep the
        // wrapper's frame, read everything else from the child.
        var target = element
        var values = outer
        if outer[AXName.role]?.string == AXName.groupRole,
           let inner = outer[AXName.children]?.elements.first {
            target = inner
            values = inner.attributes(Self.iconAttributes)
        }
        let help = values[AXName.help]?.string?.split(separator: "\n").first.map(String.init)
        return FoundIcon(
            app: app,
            element: target,
            role: outer[AXName.role]?.string,
            title: values[AXName.title]?.string?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            description: values[AXName.description]?.string,
            help: help,
            frame: frame,
            actions: target.actionNames(),
            menuElement: values[AXName.children]?.elements.first { role(of: $0) == AXName.menuRole }
        )
    }

    /// Union of an app's own menu titles (File, Edit…), which can cover icons on a narrow menu bar. Nil while the
    /// menus aren't laid out: right as an app comes to the front, only the Apple menu has a width (Figma, Oct 27:
    /// 13 menus, one sized; a second later all of them).
    func appMenusFrame(_ app: any AXElement) -> Frame? {
        guard case .success(.element(let bar)) = app.attribute(AXName.menuBar) else { return nil }
        let menus = bar.attributes([AXName.children])[AXName.children]?.elements ?? []
        var union: CGRect?
        var sized = 0
        for menu in menus {
            let values = menu.attributes([AXName.position, AXName.size])
            if let origin = values[AXName.position]?.point, let size = values[AXName.size]?.size, size.width > 0 {
                let rect = CGRect(origin: origin, size: size)
                union = union.map { $0.union(rect) } ?? rect
                sized += 1
            }
        }
        guard sized > 1 || menus.count < 2 else { return nil }
        return union.map(Frame.init)
    }

    typealias WalkedItem = (entry: MenuEntry, element: any AXElement)

    func walk(_ menu: any AXElement, depth: Int, budget: inout Int) -> [WalkedItem] {
        var result: [WalkedItem] = []
        for child in menu.attributes([AXName.children])[AXName.children]?.elements ?? [] {
            guard budget > 0 else { break }
            budget -= 1
            let values = child.attributes(Self.menuItemAttributes)
            let title = values[AXName.title]?.string
            let enabled = values[AXName.enabled]?.bool ?? true
            let submenu = values[AXName.children]?.elements.first { role(of: $0) == AXName.menuRole }
            var entry = MenuEntry(
                title: title,
                enabled: enabled,
                isSeparator: title == nil && !enabled && submenu == nil,
                mark: values[AXName.markChar]?.string,
                shortcut: values[AXName.cmdChar]?.string.map {
                    MenuPaths.shortcut(char: $0, modifiers: values[AXName.cmdModifiers]?.int ?? 0)
                }
            )
            if let submenu, depth < maxDepth {
                entry.children = walk(submenu, depth: depth + 1, budget: &budget).map(\.entry)
            }
            result.append((entry, child))
        }
        return result
    }

    func role(of element: any AXElement, attribute: String = AXName.role) -> String? {
        element.attributes([attribute])[attribute]?.string
    }

    func menuChild(of element: any AXElement) -> (any AXElement)? {
        element.attributes([AXName.children])[AXName.children]?.elements.first { role(of: $0) == AXName.menuRole }
    }

    /// Finds the entry at `titles` in an already-read menu and checks it can be run.
    @discardableResult
    func entry(
        at titles: [String], in menu: [MenuEntry], iconName: String, confirm: Bool
    ) throws -> MenuEntry {
        var level = menu
        var walked: [String] = [iconName]
        for (depth, typed) in titles.enumerated() {
            guard let match = level.first(where: {
                !$0.isSeparator && $0.title.map { MenuPaths.matches(typed, $0) } == true
            }) else {
                throw BellhopError.itemNotFound(
                    path: MenuPaths.join(walked + [typed]), available: level.compactMap(\.title)
                )
            }
            walked.append(match.title ?? typed)
            if depth == titles.count - 1 {
                try check(
                    title: match.title ?? typed, enabled: match.enabled,
                    hasSubmenu: match.children?.isEmpty == false, path: MenuPaths.join(walked), confirm: confirm
                )
                return match
            }
            level = match.children ?? []
        }
        throw BellhopError.itemNotFound(path: MenuPaths.join(walked), available: [])
    }

    /// Finds the live element at `titles`, reading titles fresh, and checks it can be run.
    func liveItem(
        at titles: [String], in menu: any AXElement, iconName: String, confirm: Bool
    ) throws -> (element: any AXElement, titles: [String]) {
        var level = menu
        var actual: [String] = []
        for (depth, typed) in titles.enumerated() {
            var budget = maxMenuItems
            let items = walk(level, depth: maxDepth, budget: &budget)
            guard let match = items.first(where: {
                !$0.entry.isSeparator && $0.entry.title.map { MenuPaths.matches(typed, $0) } == true
            }) else {
                throw BellhopError.itemNotFound(
                    path: MenuPaths.join([iconName] + actual + [typed]), available: items.compactMap(\.entry.title)
                )
            }
            actual.append(match.entry.title ?? typed)
            let submenu = menuChild(of: match.element)
            if depth == titles.count - 1 {
                try check(
                    title: match.entry.title ?? typed, enabled: match.entry.enabled, hasSubmenu: submenu != nil,
                    path: MenuPaths.join([iconName] + actual), confirm: confirm
                )
                return (match.element, actual)
            }
            guard let submenu else {
                throw BellhopError.itemNotFound(
                    path: MenuPaths.join([iconName] + actual + [titles[depth + 1]]), available: []
                )
            }
            level = submenu
        }
        throw BellhopError.badRequest("empty path")
    }

    func check(title: String, enabled: Bool, hasSubmenu: Bool, path: String, confirm: Bool) throws {
        if hasSubmenu { throw BellhopError.submenu(path) }
        if !enabled { throw BellhopError.disabled(path) }
        if MenuPaths.isDestructive(title), !confirm { throw BellhopError.needsConfirmation(path) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
