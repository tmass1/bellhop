import CoreGraphics
import Foundation
@testable import ValetCore

// Rebuilds Accessibility element trees from saved valet-probe output (Tests/Fixtures), so ValetCore runs against
// a real menu bar's shape without a live one.

struct ProbeFile: Decodable, Sendable {
    struct FrontmostApp: Decodable, Sendable {
        var pid: Int32
        var menusFrame: Frame?
    }

    struct App: Decodable, Sendable {
        var name: String
        var bundleID: String?
        var pid: Int32
        var items: [Item]
    }

    struct Item: Decodable, Sendable {
        var wrapperRole: String?
        var title: String?
        var description: String?
        var help: String?
        var role: String?
        var subrole: String?
        var frame: Frame?
        var actions: [String]
        var menu: Menu
    }

    struct Menu: Decodable, Sendable {
        var status: String
        var items: [Node]
    }

    struct Node: Decodable, Sendable {
        var title: String?
        var enabled: Bool?
        var isSeparator: Bool
        var mark: String?
        var cmdChar: String?
        var cmdModifiers: Int?
        var children: [Node]?
    }

    var screens: [ScreenGeometry]
    var frontmostApp: FrontmostApp?
    var apps: [App]

    static func load(_ name: String) throws -> ProbeFile {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try JSONDecoder().decode(ProbeFile.self, from: Data(contentsOf: url))
    }

    var system: SystemSnapshot {
        let apps = apps.map { RunningApp(name: $0.name, bundleID: $0.bundleID, pid: $0.pid) }
        return SystemSnapshot(
            apps: apps, frontmost: apps.first { $0.pid == frontmostApp?.pid }, screens: screens
        )
    }
}

/// Records every action performed on fake elements, in order: "<title or role>:<action>".
final class ActionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var entries: [String] { lock.withLock { storage } }

    func append(_ entry: String) {
        lock.withLock { storage.append(entry) }
    }
}

final class FakeElement: AXElement {
    var values: [String: AXAttributeValue]
    var actions: [String]
    /// Runs before the default handling; return a failure to simulate one.
    var onPerform: ((FakeElement, String) -> AXFailure?)?
    private let log: ActionLog

    init(_ values: [String: AXAttributeValue], actions: [String] = [], log: ActionLog) {
        self.values = values
        self.actions = actions
        self.log = log
    }

    var name: String {
        values[AXName.title]?.string ?? values[AXName.description]?.string ?? values[AXName.role]?.string ?? "?"
    }

    func attribute(_ name: String) -> Result<AXAttributeValue, AXFailure> {
        values[name].map { .success($0) } ?? .failure(.noValue)
    }

    func attributes(_ names: [String]) -> [String: AXAttributeValue] {
        values.filter { names.contains($0.key) }
    }

    func actionNames() -> [String] { actions }

    func setPosition(_ point: CGPoint) -> AXFailure? {
        log.append("\(name):setPosition(\(Int(point.x)),\(Int(point.y)))")
        values[AXName.position] = .point(point)
        return nil
    }

    func perform(_ action: String) -> AXFailure? {
        log.append("\(name):\(action)")
        if let failure = onPerform?(self, action) { return failure }
        return actions.contains(action) ? nil : .actionUnsupported
    }
}

/// Built app elements, kept per pid so state (an opened menu or window) survives between calls, as it does live.
final class AppCache: @unchecked Sendable {
    private let lock = NSLock()
    private var apps: [Int32: FakeElement] = [:]
    private var count = 0

    /// How many times an application element was asked for.
    var lookups: Int { lock.withLock { count } }

    func app(_ pid: Int32, build: () -> FakeElement) -> FakeElement {
        lock.withLock {
            count += 1
            if let app = apps[pid] { return app }
            let app = build()
            apps[pid] = app
            return app
        }
    }
}

/// Serves fixture apps. `customize` can adjust an icon's element after it's built (e.g. give it an on-demand menu,
/// or make pressing it add a window to its app, like a panel).
struct FixtureAccessibility: AccessibilitySystem {
    typealias Customize = @Sendable (
        _ appName: String, _ icon: FakeElement, _ app: FakeElement, _ log: ActionLog
    ) -> Void

    let file: ProbeFile
    let log = ActionLog()
    let cache = AppCache()
    var isTrusted = true
    var customize: Customize = { _, _, _, _ in }

    init(_ name: String) throws {
        file = try ProbeFile.load(name)
    }

    func application(pid: Int32) -> any AXElement {
        cache.app(pid) { build(pid: pid) }
    }

    private func build(pid: Int32) -> FakeElement {
        let app = FakeElement([AXName.role: .string("AXApplication"), AXName.windows: .elements([])], log: log)
        guard let fixture = file.apps.first(where: { $0.pid == pid }) else { return app }
        if !fixture.items.isEmpty {
            let icons = fixture.items.map { buildIcon($0, appName: fixture.name, app: app) }
            app.values[AXName.extrasMenuBar] = .element(
                FakeElement([AXName.role: .string("AXMenuBar"), AXName.children: .elements(icons)], log: log)
            )
        }
        if pid == file.frontmostApp?.pid, let frame = file.frontmostApp?.menusFrame {
            let menus = FakeElement(position(frame).compactMapValues { $0 }, log: log)
            app.values[AXName.menuBar] = .element(FakeElement([AXName.children: .elements([menus])], log: log))
        }
        return app
    }

    private func buildIcon(_ item: ProbeFile.Item, appName: String, app: FakeElement) -> FakeElement {
        var values = position(item.frame)
        values[AXName.role] = item.role.map { .string($0) }
        values[AXName.subrole] = item.subrole.map { .string($0) }
        values[AXName.title] = item.title.map { .string($0) }
        values[AXName.description] = item.description.map { .string($0) }
        values[AXName.help] = item.help.map { .string($0) }
        let readable = item.menu.status == "readable"
        values[AXName.children] = .elements(readable ? [Self.menu(item.menu.items, log: log)] : [])
        let icon = FakeElement(values.compactMapValues { $0 }, actions: item.actions, log: log)
        customize(appName, icon, app, log)
        guard item.wrapperRole != nil else { return icon }
        var wrapper = position(item.frame)
        wrapper[AXName.role] = .string(AXName.groupRole)
        wrapper[AXName.children] = .elements([icon])
        return FakeElement(wrapper.compactMapValues { $0 }, log: log)
    }

    static func menu(_ nodes: [ProbeFile.Node], log: ActionLog) -> FakeElement {
        let items = nodes.map { node in
            var values: [String: AXAttributeValue?] = [
                AXName.role: .string("AXMenuItem"),
                AXName.title: node.title.map { .string($0) },
                AXName.enabled: .bool(node.enabled ?? !node.isSeparator),
                AXName.markChar: node.mark.map { .string($0) },
                AXName.cmdChar: node.cmdChar.map { .string($0) },
                AXName.cmdModifiers: node.cmdModifiers.map { .int($0) },
            ]
            values[AXName.children] = .elements(node.children.map { [menu($0, log: log)] } ?? [])
            return FakeElement(values.compactMapValues { $0 }, actions: [AXName.press], log: log)
        }
        return FakeElement(
            [AXName.role: .string(AXName.menuRole), AXName.children: .elements(items)],
            actions: [AXName.cancel],
            log: log
        )
    }

    private func position(_ frame: Frame?) -> [String: AXAttributeValue?] {
        guard let frame else { return [:] }
        return [
            AXName.position: .point(CGPoint(x: frame.x, y: frame.y)),
            AXName.size: .size(CGSize(width: frame.width, height: frame.height)),
        ]
    }
}

extension ProbeFile.Node {
    static func item(_ title: String, enabled: Bool = true) -> ProbeFile.Node {
        ProbeFile.Node(title: title, enabled: enabled, isSeparator: false)
    }
}
