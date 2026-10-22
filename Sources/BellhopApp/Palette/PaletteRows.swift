import BellhopCore

/// The rows the palette shows, and the levels you can drill into.
extension PaletteModel {
    /// One runnable menu item as a row.
    struct Item: Equatable {
        var icon: MenuBarIcon
        var titles: [String]
        var entry: MenuEntry
        var key: String
        /// Offsets into `matchText` that matched the query.
        var hits: Set<Int>
        /// Inside an app's menu the breadcrumb names the app, so only the title is shown and matched.
        var local: Bool

        var matchText: String { local ? (titles.last ?? "") : MenuPaths.join([icon.name] + titles) }
        var path: String { MenuPaths.join([icon.name] + titles) }
        var isDestructive: Bool { MenuPaths.isDestructive(titles.last ?? "") }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.key == rhs.key && lhs.hits == rhs.hits }
    }

    enum Row: Identifiable, Equatable {
        case section(String, count: Int?)
        case divider(Int)
        case message(String, String)
        case loading(String)
        case icon(MenuBarIcon, hits: Set<Int>)
        case item(Item)
        /// "Show CopyClip's menu once" for apps whose menus aren't indexed.
        case reveal(MenuBarIcon)

        var id: String {
            switch self {
            case .section(let title, _): "section|\(title)"
            case .divider(let index): "divider|\(index)"
            case .message(let title, _): "message|\(title)"
            case .loading(let title): "loading|\(title)"
            case .icon(let icon, _): SearchIndex.iconKey(icon.id)
            case .item(let item): item.key
            case .reveal(let icon): "reveal|\(icon.id)"
            }
        }

        var isSelectable: Bool {
            switch self {
            case .icon, .reveal: true
            case .item(let item): item.entry.enabled
            default: false
            }
        }

        static func == (lhs: Row, rhs: Row) -> Bool { lhs.id == rhs.id }
    }

    /// One level of drilling into an app's menu.
    struct Level {
        var icon: MenuBarIcon
        var titles: [String]
        var entries: [MenuEntry]
    }
}
