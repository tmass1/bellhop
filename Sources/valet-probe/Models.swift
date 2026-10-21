import ValetCore

// The probe's JSON output. Field names are the contract with Tests/Fixtures once real outputs are saved there.

struct ProbeOutput: Codable, Sendable {
    var probeVersion = "0.1"
    var capturedAt: String
    var macOS: OSInfo
    var hardware: Hardware
    /// The app macOS grants Accessibility to when the probe runs, usually the terminal.
    var accessibilityHost: String?
    var screens: [ScreenGeometry]
    var frontmostApp: FrontmostApp?
    var options: Options
    var summary: Summary
    var apps: [AppResult]
}

struct OSInfo: Codable, Sendable {
    var version: String
    var build: String
}

struct Hardware: Codable, Sendable {
    var model: String
    var arch: String
}

struct FrontmostApp: Codable, Sendable {
    var name: String
    var bundleID: String?
    var pid: Int32
    var menuTitles: [String]
    /// Union of the app's menu bar item frames.
    var menusFrame: Frame?
}

struct Options: Codable, Sendable {
    var maxDepth: Int
    var allProcesses: Bool
    var app: String?
    var delay: Double
    var timeout: Double
}

struct Summary: Codable, Sendable {
    var appsScanned: Int
    var appsWithExtras: Int
    var itemCount: Int
    var hiddenCount: Int
    var hiddenByReason: [String: Int]
    var menuStatusCounts: [String: Int]
    var appsWithoutClosedMenu: [String]
    var appsWithErrors: [String]
    /// Processes that didn't answer, usually helpers with no Accessibility server. Normal in large numbers.
    var cannotCompleteCount: Int
    var totalMs: Double
    var slowestApps: [Timing]
}

struct Timing: Codable, Sendable {
    var name: String
    var ms: Double
}

/// A process to probe, captured on the main thread.
struct AppInfo: Codable, Sendable {
    var name: String
    var bundleID: String?
    var pid: Int32
    /// `regular`, `accessory`, `prohibited`, or `process` for pids found outside NSWorkspace.
    var activationPolicy: String
}

struct AppResult: Codable, Sendable {
    var name: String
    var bundleID: String?
    var pid: Int32
    var activationPolicy: String
    var ms: Double
    /// `ok`, `none` (no extras menu bar), `cannotComplete` (timed out or no AX server), `notTrusted`, or `error`.
    var extrasStatus: String
    var extrasError: Int32?
    var items: [Item]
}

struct Item: Codable, Sendable {
    var index: Int
    /// Set when the menu bar child was a wrapper (macOS 27 MenuBarAgent: `AXGroup/AXHostingView`) and the fields
    /// below come from the item inside it.
    var wrapperRole: String?
    var title: String?
    var description: String?
    var identifier: String?
    var help: String?
    var role: String?
    var subrole: String?
    var frame: Frame?
    var screenIndex: Int?
    var hidden: Bool
    var hiddenReasons: [HiddenReason]
    var actions: [String]
    var attributeNames: [String]
    /// Stringified values of attributes outside the known set, to spot anything new on macOS 27.
    var extraAttributes: [String: String]
    var menu: MenuResult

    /// The best human label: title, description, the tooltip's first line (many apps only set that), identifier.
    var label: String {
        title ?? description ?? help?.split(separator: "\n").first.map(String.init) ?? identifier ?? "(unlabeled)"
    }
}

struct MenuResult: Codable, Sendable {
    /// `readable`, `notExposedWhileClosed`, or `error`.
    var status: String
    var error: Int32?
    var itemCount: Int
    var truncated: Bool
    var ms: Double
    var items: [MenuNode]
}

struct MenuNode: Codable, Sendable {
    var title: String?
    var role: String?
    var subrole: String?
    var identifier: String?
    var enabled: Bool?
    /// Heuristic: an untitled, disabled menu item with no children.
    var isSeparator: Bool
    var mark: String?
    var shortcut: String?
    var cmdChar: String?
    var cmdModifiers: Int?
    var cmdVirtualKey: Int?
    var children: [MenuNode]?
    /// True when the submenu exists but `--max-depth` stopped the walk.
    var depthLimited: Bool?
}
