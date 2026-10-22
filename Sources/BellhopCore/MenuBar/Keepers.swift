import Foundation

/// Keepers: tucked icons you chose to keep, shown again as Bellhop's own status items.
public enum KeeperLayout {
    /// Preferred positions for keepers, in the order you want them left to right. macOS sorts items by this number
    /// (larger is further left), so they fall between the divider (icon + 0.5) and Bellhop's icon (icon + 0).
    public static func positions(count: Int, iconPosition: Double) -> [Double] {
        guard count > 0 else { return [] }
        let step = count > 1 ? 0.4 / Double(count - 1) : 0
        // Rounded: these are written to defaults, and 250.25000000000003 helps no one.
        return (0..<count).map { ((iconPosition + 0.45 - step * Double($0)) * 1000).rounded() / 1000 }
    }
}

extension MenuBarIcon {
    /// Text worth showing on a keeper: the icon's own title when it reads like a live value (Burn's "56%",
    /// Fritter's "3"). Long titles are labels, not status ("Apple Passwords Key"), so those fall back to the app icon.
    public var statusText: String? {
        guard let title, title != name else { return nil }
        let short = title.count <= 4
        let numeric = title.contains { $0.isNumber } && title.count <= 12
        return short || numeric ? title : nil
    }
}

extension MenuBarEngine {
    /// Re-reads the titles of a few icons from the last scan, for keepers' status text. One Accessibility call
    /// per icon, so it's cheap enough to run every 30 seconds. Icons whose app went away are left out.
    public func titles(of ids: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for id in ids {
            guard let title = liveTitle(of: id) else { continue }
            result[id] = title
        }
        return result
    }
}
