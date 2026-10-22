import Foundation

/// How Valet's divider tucks icons away. Pure numbers, so it's testable without a menu bar.
///
/// Spike results (macOS 27.0.1, Oct 21): macOS orders status items by their stored preferred position, larger
/// meaning further left. A divider at the icon's position + 0.5 lands directly left of it. When the divider is
/// wider than the room left of Valet's icon, macOS collapses it and everything to its left behind the overflow
/// arrow. Much wider (700 pt and up on a 771 pt bar) breaks the layout, so it's sized just past the room.
public enum DividerLayout {
    /// Extra width past the room, so small changes (a clock tick, a new icon) don't let it fit again.
    public static let margin = 40.0
    /// Width while arranging: a thin line you can see and drag past.
    public static let arrangingWidth = 12.0

    /// The divider's preferred position for a given Valet icon position: directly left of it.
    public static func dividerPosition(forIcon position: Double) -> Double {
        position + 0.5
    }

    /// Where the room left of Valet's icon starts: the notch's right edge on notched screens, otherwise the end
    /// of the frontmost app's menus (they share the bar), otherwise the screen's left edge.
    public static func leftBoundary(screenMinX: Double, notchMaxX: Double?, appMenusMaxX: Double?) -> Double {
        if let notchMaxX { return notchMaxX }
        return max(screenMinX, appMenusMaxX ?? screenMinX)
    }

    /// The width that makes macOS collapse the divider and everything left of it, or nil if Valet's icon has no
    /// room to its left (it's collapsed itself, or not laid out yet).
    public static func tuckingWidth(iconMinX: Double, leftBoundary: Double) -> Double? {
        let room = iconMinX - leftBoundary
        guard room > 1 else { return nil }
        return (room + margin).rounded(.up)
    }
}

/// A scan split the way the Valet menu shows it.
public struct MenuBarSections: Sendable {
    /// Behind the overflow arrow, under the notch, or otherwise out of sight. Left to right.
    public var tucked: [MenuBarIcon]
    /// Visible in the menu bar. Left to right.
    public var inBar: [MenuBarIcon]

    public init(_ snapshot: MenuBarSnapshot) {
        tucked = snapshot.icons.filter(\.isHidden)
        inBar = snapshot.icons.filter { !$0.isHidden }
    }
}
