import Foundation

/// Menu paths like "Mark › Settings…": the icon's name, then each menu title down to the item.
public enum MenuPaths {
    public static let separator = " › "

    /// Splits a typed path on "›" or ">", trimming spaces.
    public static func parse(_ query: String) -> [String] {
        query
            .split(whereSeparator: { $0 == "›" || $0 == ">" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func join(_ components: [String]) -> String {
        components.joined(separator: separator)
    }

    /// Case-insensitive, whitespace-insensitive, and forgiving about a trailing ellipsis ("Settings…" = "settings").
    public static func matches(_ typed: String, _ title: String) -> Bool {
        normalize(typed) == normalize(title)
    }

    static func normalize(_ text: String) -> String {
        var result = text.lowercased()
            .replacingOccurrences(of: "\u{2011}", with: "-") // non-breaking hyphen, as in "Wi‑Fi"
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for suffix in ["…", "..."] where result.hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// Every runnable entry under an icon, in menu order: titled items without submenus. Separators are skipped.
    public static func entries(for icon: MenuBarIcon) -> [(titles: [String], entry: MenuEntry)] {
        var result: [(titles: [String], entry: MenuEntry)] = []
        func walk(_ entries: [MenuEntry], prefix: [String]) {
            for entry in entries where !entry.isSeparator {
                guard let title = entry.title else { continue }
                if let children = entry.children, !children.isEmpty {
                    walk(children, prefix: prefix + [title])
                } else {
                    result.append((prefix + [title], entry))
                }
            }
        }
        walk(icon.menu ?? [], prefix: [])
        return result
    }

    /// Full display paths for every runnable entry, e.g. "Mark › Capture Region".
    public static func displayPaths(for icon: MenuBarIcon) -> [String] {
        entries(for: icon).map { join([icon.name] + $0.titles) }
    }

    /// Items that need ⌘Return or `--confirm`, so a mistyped search can't quit or erase something.
    public static func isDestructive(_ title: String) -> Bool {
        let words = normalize(title)
        return destructivePrefixes.contains { words == $0 || words.hasPrefix($0 + " ") }
    }

    private static let destructivePrefixes = [
        "quit", "delete", "sign out", "log out", "reset", "erase", "remove", "restart", "shut down", "empty",
    ]

    /// Finds the icon a path starts with: by name, label, app name, then bundle ID.
    public static func resolveIcon(_ typed: String, in icons: [MenuBarIcon]) throws -> MenuBarIcon {
        let keys: [(MenuBarIcon) -> String?] = [\.name, \.label, \.app.name, \.app.bundleID]
        for key in keys {
            let found = icons.filter { icon in key(icon).map { matches(typed, $0) } ?? false }
            if found.count == 1 { return found[0] }
            if found.count > 1 { throw ValetError.ambiguous(typed, found.map(\.label)) }
        }
        throw ValetError.iconNotFound(typed)
    }

    /// Renders AXMenuItemCmdModifiers the way menus show them, e.g. ⌃⌥⇧⌘K. Bit 3 means no ⌘.
    static func shortcut(char: String, modifiers: Int) -> String {
        var glyphs = ""
        if modifiers & 4 != 0 { glyphs += "⌃" }
        if modifiers & 2 != 0 { glyphs += "⌥" }
        if modifiers & 1 != 0 { glyphs += "⇧" }
        if modifiers & 8 == 0 { glyphs += "⌘" }
        return glyphs + char
    }
}
