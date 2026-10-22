import CoreGraphics
import Foundation

/// The result of `MenuBarEngine.run`.
public struct RunResult: Codable, Sendable, Equatable {
    /// The path as the menu titles it, e.g. "Mark › Settings…".
    public var path: String
    /// True when Valet had to open the menu to reach the item.
    public var openedMenu: Bool
}

/// Scans menu bar icons, reads their menus, and presses items. Every Accessibility call in Valet happens inside
/// this actor, off the main thread.
public actor MenuBarEngine {
    private let system: any AccessibilitySystem
    private var current: MenuBarSnapshot?
    /// Live elements from the last scan, by icon ID. Valid while the owning process lives.
    private var elements: [String: any AXElement] = [:]
    /// Icons that showed no menu when pressed. Remembered so we don't press them again to look.
    private var panelIcons: Set<String> = []

    private let reader = AXReader()
    private let menuOpenTimeout: Duration = .milliseconds(800)

    public init(system: any AccessibilitySystem) {
        self.system = system
    }

    // MARK: Scanning

    /// Reads every menu bar icon. Menus exposed while closed are read too; others are left for `loadMenu`.
    public func scan(_ env: SystemSnapshot) throws -> MenuBarSnapshot {
        guard system.isTrusted else { throw ValetError.notTrusted }
        let clock = ContinuousClock()
        let start = clock.now

        var found: [AXReader.FoundIcon] = []
        var overflowButton: Frame?
        for app in env.apps {
            guard case .success(.element(let bar)) = system.application(pid: app.pid).attribute(AXName.extrasMenuBar)
            else { continue }
            for element in bar.attributes([AXName.children])[AXName.children]?.elements ?? [] {
                let icon = reader.read(element, app: app)
                // macOS 27's "Show Hidden Menu Bar Items" arrow: matched by owner and role, not its localized label.
                if app.bundleID == "com.apple.MenuBarAgent", icon.role == AXName.buttonRole {
                    overflowButton = icon.frame
                } else {
                    found.append(icon)
                }
            }
        }

        let appMenus = env.frontmost.flatMap { reader.appMenusFrame(system.application(pid: $0.pid)) }
        let iconsPerApp = Dictionary(grouping: found, by: \.app.pid).mapValues(\.count)
        var indexInApp: [Int32: Int] = [:]
        var icons: [MenuBarIcon] = []
        elements = [:]
        for raw in found {
            let index = indexInApp[raw.app.pid, default: 0]
            indexInApp[raw.app.pid] = index + 1
            let id = "\(raw.app.bundleID ?? raw.app.name)#\(index)"
            elements[id] = raw.element
            let hiddenReasons = raw.frame.map {
                Visibility.hiddenReasons(
                    for: $0, screens: env.screens, appMenus: appMenus, overflowButton: overflowButton
                )
            } ?? [.offScreen]
            icons.append(icon(
                from: raw, id: id, sharesApp: (iconsPerApp[raw.app.pid] ?? 1) > 1,
                screens: env.screens, hiddenReasons: hiddenReasons
            ))
        }

        let snapshot = MenuBarSnapshot(
            capturedAt: .now,
            screens: env.screens,
            overflowButton: overflowButton,
            icons: icons.sorted { ($0.frame?.x ?? .infinity) < ($1.frame?.x ?? .infinity) },
            scanMs: (clock.now - start).milliseconds
        )
        current = snapshot
        return snapshot
    }

    private func icon(
        from raw: AXReader.FoundIcon, id: String, sharesApp: Bool, screens: [ScreenGeometry],
        hiddenReasons: [HiddenReason]
    ) -> MenuBarIcon {
        let label = raw.title ?? raw.description ?? raw.help ?? raw.app.name
        var availability = MenuAvailability.onDemand
        var menu: [MenuEntry]?
        if let menuElement = raw.menuElement {
            var budget = reader.maxMenuItems
            menu = reader.walk(menuElement, depth: 1, budget: &budget).map(\.entry)
            availability = .readable
        } else if panelIcons.contains(id) {
            availability = .panel
        }
        return MenuBarIcon(
            id: id,
            app: raw.app,
            name: sharesApp ? label : raw.app.name,
            label: label,
            title: raw.title,
            frame: raw.frame,
            screenIndex: raw.frame.flatMap { Visibility.screen(containing: $0, in: screens)?.index },
            hiddenReasons: hiddenReasons,
            menuAvailability: availability,
            menu: menu,
            canPress: raw.actions.contains(AXName.press)
        )
    }

    /// The last scan if it's recent enough, otherwise a fresh one.
    public func snapshot(_ env: SystemSnapshot, maxAge: TimeInterval = 5) throws -> MenuBarSnapshot {
        if let current, current.capturedAt.timeIntervalSinceNow > -maxAge { return current }
        return try scan(env)
    }

    // MARK: Menus

    /// Returns the icon with its menu filled in. Menus that only exist while open are opened briefly, read, and
    /// closed again, so this can flicker; call it only when someone asks for that menu.
    public func loadMenu(_ query: String, env: SystemSnapshot) async throws -> MenuBarIcon {
        let snapshot = try self.snapshot(env)
        var icon = try MenuPaths.resolveIcon(query, in: snapshot.icons)
        guard icon.menuAvailability == .onDemand, let element = elements[icon.id] else { return icon }

        guard let menuElement = await openMenu(element, iconID: icon.id) else {
            icon.menuAvailability = .panel
            update(icon)
            return icon
        }
        var budget = reader.maxMenuItems
        icon.menu = reader.walk(menuElement, depth: 1, budget: &budget).map(\.entry)
        close(menuElement, icon: element)
        update(icon)
        return icon
    }

    // MARK: Running

    /// Presses the item at `path` ("Mark › Settings…"), or the icon itself when the path is just its name.
    public func run(_ path: String, confirm: Bool, env: SystemSnapshot) async throws -> RunResult {
        let components = MenuPaths.parse(path)
        guard let first = components.first else { throw ValetError.badRequest("empty path") }
        let snapshot = try self.snapshot(env)
        let icon = try MenuPaths.resolveIcon(first, in: snapshot.icons)
        guard let iconElement = elements[icon.id] else { throw ValetError.iconNotFound(first) }

        let titles = Array(components.dropFirst())
        if titles.isEmpty {
            if let failure = iconElement.perform(AXName.press), failure != .cannotComplete {
                throw ValetError.pressFailed(icon.name, code: failure.code)
            }
            return RunResult(path: icon.name, openedMenu: false)
        }

        switch icon.menuAvailability {
        case .panel:
            throw ValetError.panelApp(icon.name)
        case .readable:
            // Check against the menu we already read before touching anything live.
            _ = try reader.entry(at: titles, in: icon.menu ?? [], iconName: icon.name, confirm: confirm)
            guard let menuElement = reader.menuChild(of: iconElement) else { throw ValetError.panelApp(icon.name) }
            let (item, actual) = try reader.liveItem(
                at: titles, in: menuElement, iconName: icon.name, confirm: confirm
            )
            // cannotComplete usually means the item's action is still running (a window or alert opening): it worked.
            let failure = item.perform(AXName.press)
            if failure == nil || failure == .cannotComplete {
                return RunResult(path: MenuPaths.join([icon.name] + actual), openedMenu: false)
            }
            // Some apps only act on items in an open menu; open it and try once more.
            return try await pressInOpenMenu(icon: icon, iconElement: iconElement, titles: titles, confirm: confirm)
        case .onDemand:
            return try await pressInOpenMenu(icon: icon, iconElement: iconElement, titles: titles, confirm: confirm)
        }
    }

    private func pressInOpenMenu(
        icon: MenuBarIcon, iconElement: any AXElement, titles: [String], confirm: Bool
    ) async throws -> RunResult {
        guard let menuElement = await openMenu(iconElement, iconID: icon.id) else {
            var panel = icon
            panel.menuAvailability = .panel
            update(panel)
            throw ValetError.panelApp(icon.name)
        }
        do {
            let (item, actual) = try reader.liveItem(at: titles, in: menuElement, iconName: icon.name, confirm: confirm)
            let path = MenuPaths.join([icon.name] + actual)
            if let failure = item.perform(AXName.press), failure != .cannotComplete {
                close(menuElement, icon: iconElement)
                throw ValetError.pressFailed(path, code: failure.code)
            }
            return RunResult(path: path, openedMenu: true)
        } catch {
            close(menuElement, icon: iconElement)
            throw error
        }
    }

    // MARK: Opening and closing

    /// Presses the icon and waits for its menu. Returns nil for panel apps, after closing the panel again.
    private func openMenu(_ icon: any AXElement, iconID: String) async -> (any AXElement)? {
        // An open menu holds the owning app in menu tracking, so this press often times out (cannotComplete)
        // even though it worked.
        if let failure = icon.perform(AXName.press), failure != .cannotComplete { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now + menuOpenTimeout
        while clock.now < deadline {
            if let menu = reader.menuChild(of: icon) { return menu }
            try? await Task.sleep(for: .milliseconds(40))
        }
        // No menu appeared: it's a panel or popover. Pressing again toggles it closed.
        panelIcons.insert(iconID)
        _ = icon.perform(AXName.press)
        return nil
    }

    private func close(_ menu: any AXElement, icon: any AXElement) {
        if menu.perform(AXName.cancel) != nil, reader.menuChild(of: icon) != nil {
            _ = icon.perform(AXName.press)
        }
    }

    private func update(_ icon: MenuBarIcon) {
        guard var snapshot = current, let index = snapshot.icons.firstIndex(where: { $0.id == icon.id }) else {
            return
        }
        snapshot.icons[index] = icon
        current = snapshot
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return ((Double(seconds) * 1000 + Double(attoseconds) / 1e15) * 10).rounded() / 10
    }
}
