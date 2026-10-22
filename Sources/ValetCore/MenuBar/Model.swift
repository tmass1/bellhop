import Foundation

/// A process that may own menu bar icons.
public struct RunningApp: Codable, Sendable, Hashable {
    public var name: String
    public var bundleID: String?
    public var pid: Int32

    public init(name: String, bundleID: String?, pid: Int32) {
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
    }
}

/// What the scanner needs from AppKit, captured on the main thread.
public struct SystemSnapshot: Sendable {
    public var apps: [RunningApp]
    public var frontmost: RunningApp?
    public var screens: [ScreenGeometry]
    /// Where Valet's own dividers are, in Accessibility coordinates. An icon overlapping one is tucked: collapsed
    /// icons can keep reporting their old position, and macOS never lets two items overlap.
    public var dividers: [Frame]

    public init(apps: [RunningApp], frontmost: RunningApp?, screens: [ScreenGeometry], dividers: [Frame] = []) {
        self.apps = apps
        self.frontmost = frontmost
        self.screens = screens
        self.dividers = dividers
    }
}

public enum MenuAvailability: String, Codable, Sendable {
    /// The menu is exposed while closed and has been read.
    case readable
    /// The app only builds its menu when it opens. `MenuBarEngine.loadMenu` opens it briefly to read it.
    case onDemand
    /// Pressing the icon opens a window (panel, popover or overlay) instead of a menu. Run the icon itself.
    case panel
    /// Pressing the icon over Accessibility did nothing visible to Valet; some apps only react to real clicks.
    case noResponse
}

public struct MenuEntry: Codable, Sendable, Equatable {
    public var title: String?
    public var enabled: Bool
    public var isSeparator: Bool
    /// Checkmark or other mark, e.g. "✓".
    public var mark: String?
    /// e.g. "⌘," or "⌃⌥K".
    public var shortcut: String?
    public var children: [MenuEntry]?

    public init(
        title: String?, enabled: Bool, isSeparator: Bool = false, mark: String? = nil, shortcut: String? = nil,
        children: [MenuEntry]? = nil
    ) {
        self.title = title
        self.enabled = enabled
        self.isSeparator = isSeparator
        self.mark = mark
        self.shortcut = shortcut
        self.children = children
    }
}

public struct MenuBarIcon: Codable, Sendable, Identifiable {
    /// Stable within a scan: bundle ID (or name) plus the icon's index among that app's icons.
    public var id: String
    public var app: RunningApp
    /// What people call it: the app's name, or the icon's label when the app owns several (MenuBarAgent's Battery,
    /// Wi‑Fi, Clock). First component of every menu path.
    public var name: String
    /// Best available label: title, description, the tooltip's first line, then the app name.
    public var label: String
    /// The icon's own title text, if it shows one (e.g. Burn's "52%"). Live status for the palette.
    public var title: String?
    public var frame: Frame?
    public var screenIndex: Int?
    public var hiddenReasons: [HiddenReason]
    public var menuAvailability: MenuAvailability
    public var menu: [MenuEntry]?
    public var canPress: Bool

    public var isHidden: Bool { !hiddenReasons.isEmpty }
}

public struct MenuBarSnapshot: Codable, Sendable {
    public var capturedAt: Date
    public var screens: [ScreenGeometry]
    /// macOS 27's overflow arrow, when icons don't fit.
    public var overflowButton: Frame?
    /// Left to right.
    public var icons: [MenuBarIcon]
    public var scanMs: Double
}
