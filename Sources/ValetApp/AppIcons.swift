import AppKit
import ValetCore

/// 16 pt images for the Valet menu: the owning app's icon, or an SF Symbol for Apple's own menu bar items, which
/// all belong to one background process.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    private static let systemSymbols: [(prefix: String, symbol: String)] = [
        ("battery", "battery.100percent"), ("wi", "wifi"), ("control center", "switch.2"), ("clock", "clock"),
        ("spotlight", "magnifyingglass"), ("custom recording", "record.circle"), ("now playing", "play.circle"),
        ("bluetooth", "wave.3.right"), ("sound", "speaker.wave.2"), ("focus", "moon"),
    ]

    static func image(for icon: MenuBarIcon) -> NSImage? {
        let key = "\(icon.app.pid)|\(icon.name)"
        if let cached = cache[key] { return cached }
        let image = symbol(for: icon) ?? appIcon(pid: icon.app.pid)
        image?.size = NSSize(width: 16, height: 16)
        cache[key] = image
        return image
    }

    private static func symbol(for icon: MenuBarIcon) -> NSImage? {
        let systemOwners: Set<String?> = ["com.apple.MenuBarAgent", "com.apple.campo"]
        guard systemOwners.contains(icon.app.bundleID) else { return nil }
        let name = icon.name.lowercased()
        guard let match = systemSymbols.first(where: { name.hasPrefix($0.prefix) }) else { return nil }
        return NSImage(systemSymbolName: match.symbol, accessibilityDescription: icon.name)
    }

    private static func appIcon(pid: Int32) -> NSImage? {
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        return icon.copy() as? NSImage
    }
}
