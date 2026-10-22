import AppKit

/// Valet's own light or dark look, independent of the rest of the Mac if you like. It covers every Valet window
/// and the app menus Valet mirrors; the menu bar itself always follows the system.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "ValetAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var current: Appearance {
        UserDefaults.standard.string(forKey: key).flatMap(Appearance.init) ?? .system
    }

    @MainActor
    static func apply(_ appearance: Appearance = current) {
        UserDefaults.standard.set(appearance.rawValue, forKey: key)
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
