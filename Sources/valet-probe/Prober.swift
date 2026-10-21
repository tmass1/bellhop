import ApplicationServices
import Foundation
import ValetCore

/// Reads menu bar extras over Accessibility. Every AX call in the probe happens inside this actor, off the main thread.
actor Prober {
    private let maxDepth: Int
    private let timeout: Float
    /// Stops runaway walks of enormous menus.
    private let maxMenuItemsPerApp = 2000

    private static let itemAttributes = [
        kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXHelpAttribute,
        kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
    ]
    private static let menuItemAttributes = [
        kAXTitleAttribute, kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute, kAXEnabledAttribute,
        kAXMenuItemMarkCharAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdVirtualKeyAttribute, kAXChildrenAttribute,
    ]
    /// Attributes that are either recorded as fields or are structural. Anything else lands in `extraAttributes`.
    private static let knownAttributes: Set<String> = Set(itemAttributes + [
        kAXRoleDescriptionAttribute, kAXParentAttribute, kAXTopLevelUIElementAttribute, kAXWindowAttribute,
        kAXEnabledAttribute, kAXSelectedAttribute, kAXFocusedAttribute, "AXFrame",
    ])

    init(maxDepth: Int, timeout: Double) {
        self.maxDepth = maxDepth
        self.timeout = Float(timeout)
        // Backstop for any element that doesn't get its own timeout.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Float(timeout))
    }

    // MARK: Frontmost app

    func frontmostMenus(of app: AppInfo) -> FrontmostApp {
        let appElement = element(for: app.pid)
        var titles: [String] = []
        var union: CGRect?
        if case .success(let bar) = AX.value(appElement, kAXMenuBarAttribute) {
            // swiftlint:disable:next force_cast
            for menu in AX.elements(AX.values(bar as! AXUIElement, [kAXChildrenAttribute])[kAXChildrenAttribute]) {
                let values = AX.values(menu, [kAXTitleAttribute, kAXPositionAttribute, kAXSizeAttribute])
                if let title = AX.string(values[kAXTitleAttribute]) { titles.append(title) }
                if let origin = AX.point(values[kAXPositionAttribute]), let size = AX.size(values[kAXSizeAttribute]),
                   size.width > 0 {
                    let rect = CGRect(origin: origin, size: size)
                    union = union.map { $0.union(rect) } ?? rect
                }
            }
        }
        return FrontmostApp(
            name: app.name, bundleID: app.bundleID, pid: app.pid, menuTitles: titles, menusFrame: union.map(Frame.init)
        )
    }

    // MARK: Extras

    func probe(_ app: AppInfo, screens: [ScreenGeometry], appMenus: Frame?) -> AppResult {
        let clock = ContinuousClock()
        let start = clock.now
        let appElement = element(for: app.pid)
        var result = AppResult(
            name: app.name, bundleID: app.bundleID, pid: app.pid, activationPolicy: app.activationPolicy,
            ms: 0, extrasStatus: "ok", items: []
        )

        switch AX.value(appElement, kAXExtrasMenuBarAttribute) {
        case .success(let bar):
            // swiftlint:disable:next force_cast
            let children = AX.elements(AX.values(bar as! AXUIElement, [kAXChildrenAttribute])[kAXChildrenAttribute])
            var budget = maxMenuItemsPerApp
            result.items = children.enumerated().map { index, el in
                item(el, index: index, screens: screens, appMenus: appMenus, budget: &budget)
            }
        case .failure(let failure):
            result.extrasStatus = Self.status(for: failure.code)
            if result.extrasStatus == "error" { result.extrasError = failure.code.rawValue }
        }

        result.ms = (clock.now - start).milliseconds
        return result
    }

    private func item(
        _ el: AXUIElement, index: Int, screens: [ScreenGeometry], appMenus: Frame?, budget: inout Int
    ) -> Item {
        let outer = AX.values(el, Self.itemAttributes)
        var frame: Frame?
        if let origin = AX.point(outer[kAXPositionAttribute]), let size = AX.size(outer[kAXSizeAttribute]) {
            frame = Frame(CGRect(origin: origin, size: size))
        }
        let reasons = frame.map { Visibility.hiddenReasons(for: $0, screens: screens, appMenus: appMenus) } ?? []

        // macOS 27's MenuBarAgent wraps each system item in an AXGroup (AXHostingView); the real item is its child.
        // Read labels, actions and the menu from that child, but keep the wrapper's frame.
        var element = el
        var values = outer
        var wrapperRole: String?
        if AX.string(outer[kAXRoleAttribute]) == kAXGroupRole,
           let inner = AX.elements(outer[kAXChildrenAttribute]).first {
            wrapperRole = [AX.string(outer[kAXRoleAttribute]), AX.string(outer[kAXSubroleAttribute])]
                .compactMap { $0 }.joined(separator: "/")
            element = inner
            values = AX.values(inner, Self.itemAttributes)
        }

        let attributeNames = AX.attributeNames(element)
        var extras: [String: String] = [:]
        for name in attributeNames where !Self.knownAttributes.contains(name) {
            if case .success(let value) = AX.value(element, name) { extras[name] = AX.describe(value) }
        }

        return Item(
            index: index,
            wrapperRole: wrapperRole,
            title: AX.string(values[kAXTitleAttribute]),
            description: AX.string(values[kAXDescriptionAttribute]),
            identifier: AX.string(values[kAXIdentifierAttribute]),
            help: AX.string(values[kAXHelpAttribute]),
            role: AX.string(values[kAXRoleAttribute]),
            subrole: AX.string(values[kAXSubroleAttribute]),
            frame: frame,
            screenIndex: frame.flatMap { Visibility.screen(containing: $0, in: screens)?.index },
            hidden: frame == nil || !reasons.isEmpty,
            hiddenReasons: frame == nil ? [.offScreen] : reasons,
            actions: AX.actionNames(element),
            attributeNames: attributeNames,
            extraAttributes: extras,
            menu: menu(children: AX.elements(values[kAXChildrenAttribute]), budget: &budget)
        )
    }

    // MARK: Menus

    /// Walks the item's menu as it exists while closed. Reads only: nothing is opened or pressed.
    private func menu(children: [AXUIElement], budget: inout Int) -> MenuResult {
        let clock = ContinuousClock()
        let start = clock.now
        guard let menu = children.first(where: { role(of: $0) == kAXMenuRole }) else {
            return MenuResult(
                status: "notExposedWhileClosed", itemCount: 0, truncated: false,
                ms: (clock.now - start).milliseconds, items: []
            )
        }
        var count = 0
        var truncated = false
        let items = walk(menu, depth: 1, count: &count, budget: &budget, truncated: &truncated)
        return MenuResult(
            status: "readable", itemCount: count, truncated: truncated, ms: (clock.now - start).milliseconds,
            items: items
        )
    }

    private func walk(
        _ menu: AXUIElement, depth: Int, count: inout Int, budget: inout Int, truncated: inout Bool
    ) -> [MenuNode] {
        let children = AX.elements(AX.values(menu, [kAXChildrenAttribute])[kAXChildrenAttribute])
        var nodes: [MenuNode] = []
        for child in children {
            guard budget > 0 else {
                truncated = true
                break
            }
            budget -= 1
            count += 1
            let values = AX.values(child, Self.menuItemAttributes)
            let title = AX.string(values[kAXTitleAttribute])
            let enabled = AX.bool(values[kAXEnabledAttribute])
            let cmdChar = AX.string(values[kAXMenuItemCmdCharAttribute])
            let modifiers = AX.int(values[kAXMenuItemCmdModifiersAttribute])
            let submenu = AX.elements(values[kAXChildrenAttribute]).first { role(of: $0) == kAXMenuRole }

            var node = MenuNode(
                title: title,
                role: AX.string(values[kAXRoleAttribute]),
                subrole: AX.string(values[kAXSubroleAttribute]),
                identifier: AX.string(values[kAXIdentifierAttribute]),
                enabled: enabled,
                isSeparator: title == nil && enabled == false && submenu == nil,
                mark: AX.string(values[kAXMenuItemMarkCharAttribute]),
                shortcut: cmdChar.map { Self.shortcut(char: $0, modifiers: modifiers ?? 0) },
                cmdChar: cmdChar,
                cmdModifiers: cmdChar == nil ? nil : modifiers,
                cmdVirtualKey: AX.int(values[kAXMenuItemCmdVirtualKeyAttribute])
            )
            if let submenu {
                if depth < maxDepth {
                    node.children = walk(
                        submenu, depth: depth + 1, count: &count, budget: &budget, truncated: &truncated
                    )
                } else {
                    node.depthLimited = true
                }
            }
            nodes.append(node)
        }
        return nodes
    }

    // MARK: Helpers

    private func element(for pid: Int32) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, timeout)
        return el
    }

    private func role(of el: AXUIElement) -> String? {
        AX.string(AX.values(el, [kAXRoleAttribute])[kAXRoleAttribute])
    }

    private static func status(for err: AXError) -> String {
        switch err {
        case .attributeUnsupported, .noValue: "none"
        case .cannotComplete: "cannotComplete"
        case .apiDisabled: "notTrusted"
        default: "error"
        }
    }

    /// Renders AXMenuItemCmdModifiers the way menus show them, e.g. ⌃⌥⇧⌘K. Bit 3 means no ⌘.
    private static func shortcut(char: String, modifiers: Int) -> String {
        var glyphs = ""
        if modifiers & 4 != 0 { glyphs += "⌃" }
        if modifiers & 2 != 0 { glyphs += "⌥" }
        if modifiers & 1 != 0 { glyphs += "⇧" }
        if modifiers & 8 == 0 { glyphs += "⌘" }
        return glyphs + char
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return ((Double(seconds) * 1000 + Double(attoseconds) / 1e15) * 10).rounded() / 10
    }
}
