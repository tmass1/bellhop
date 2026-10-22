import AppKit
import ValetCore

/// State behind the palette: what's typed, which app's menu you've drilled into, the rows, and the selection.
@MainActor
@Observable
final class PaletteModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            confirming = nil
            rebuild(keepingSelection: false)
        }
    }
    private(set) var stack: [Level] = []
    private(set) var rows: [Row] = []
    var selection: Int?
    /// The destructive item waiting for a second Return.
    private(set) var confirming: String?
    private(set) var history: History

    @ObservationIgnored private var snapshot: MenuBarSnapshot?
    @ObservationIgnored private var index = SearchIndex(icons: [])
    @ObservationIgnored private var kept: [String] = []
    @ObservationIgnored private var revealed: Set<String> = []
    @ObservationIgnored private var reading: String?
    @ObservationIgnored private let store = HistoryStore()

    // What the controller does.
    @ObservationIgnored var onRun: ((Item) -> Void)?
    @ObservationIgnored var onOpen: ((MenuBarIcon) -> Void)?
    @ObservationIgnored var onRead: ((MenuBarIcon) async -> MenuBarIcon?)?
    @ObservationIgnored var onClose: (() -> Void)?

    init() {
        history = store.load()
    }

    var selectedRow: Row? { selection.flatMap { rows.indices.contains($0) ? rows[$0] : nil } }
    var currentLevel: Level? { stack.last }

    // MARK: Data

    func update(snapshot: MenuBarSnapshot, kept: [String]) {
        self.snapshot = snapshot
        self.kept = kept
        index = SearchIndex(icons: snapshot.icons)
        // Keep a drilled-in level pointing at the fresh icon (its menu may have been read meanwhile).
        stack = stack.map { level in
            guard var icon = snapshot.icons.first(where: { $0.id == level.icon.id }) else { return level }
            if icon.menu == nil { icon.menu = level.icon.menu }
            return Level(icon: icon, titles: level.titles, entries: level.entries)
        }
        rebuild(keepingSelection: true)
    }

    /// Back to the empty state, for the next time the palette opens.
    func reset() {
        stack = []
        confirming = nil
        if query.isEmpty { rebuild(keepingSelection: false) } else { query = "" }
    }

    // MARK: Rows

    private func rebuild(keepingSelection: Bool) {
        let selectedID = keepingSelection ? selectedRow?.id : nil
        rows = stack.isEmpty ? (query.trimmingCharacters(in: .whitespaces).isEmpty ? emptyState() : results())
            : levelRows()
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
            selection = index
        } else {
            selection = rows.firstIndex(where: \.isSelectable)
        }
    }

    private func emptyState() -> [Row] {
        guard let snapshot else { return [.loading("Reading the menu bar…")] }
        var rows: [Row] = []
        let pinned = history.pins.compactMap(row(forKey:))
        if !pinned.isEmpty { rows += [.section("Pinned", count: nil)] + pinned }
        let recent = history.recent(limit: 3).filter { !history.isPinned($0) }.compactMap(row(forKey:))
        if !recent.isEmpty { rows += [.section("Recent", count: nil)] + recent }
        let sections = MenuBarSections(snapshot)
        let tucked = sections.tucked.filter { !kept.contains($0.id) }
        let byID = Dictionary(snapshot.icons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inBar = kept.compactMap { byID[$0] } + sections.inBar.filter { !kept.contains($0.id) }
        if !tucked.isEmpty {
            rows += [.section("Tucked Away", count: tucked.count)] + tucked.map { .icon($0, hits: []) }
        }
        rows += [.section("In the Menu Bar", count: nil)] + inBar.map { .icon($0, hits: []) }
        return rows
    }

    private func row(forKey key: String) -> Row? {
        guard let candidate = index.candidate(forKey: key) else { return nil }
        switch candidate.kind {
        case .icon:
            return .icon(candidate.icon, hits: [])
        case .item:
            guard let entry = candidate.entry else { return nil }
            return .item(Item(
                icon: candidate.icon, titles: candidate.titles, entry: entry, key: key, hits: [], local: false
            ))
        }
    }

    private func results() -> [Row] {
        var rows: [Row] = index.search(query, boosts: history.boosts()).compactMap { result in
            let candidate = result.candidate
            switch candidate.kind {
            case .icon:
                return .icon(candidate.icon, hits: result.hits)
            case .item:
                guard let entry = candidate.entry else { return nil }
                return .item(Item(
                    icon: candidate.icon, titles: candidate.titles, entry: entry, key: candidate.key,
                    hits: result.hits, local: false
                ))
            }
        }
        // Menus only built when opened can't match until Valet has read them once. Say so when nothing in a
        // menu matched, and let → read them.
        let anyItem = rows.contains { if case .item = $0 { true } else { false } }
        if rows.isEmpty { rows.append(.message("No matches", "Nothing Valet has read matches “\(query)”.")) }
        let unread = (snapshot?.icons ?? []).filter {
            $0.menuAvailability == .onDemand && $0.menu == nil && !index.isPrivate($0)
        }
        if !anyItem, !unread.isEmpty {
            rows += [.section("Menus Not Read Yet", count: nil)] + unread.map { .icon($0, hits: []) }
        }
        return rows
    }

    private func levelRows() -> [Row] {
        guard let level = stack.last else { return [] }
        let icon = level.icon
        if index.isPrivate(icon), !revealed.contains(icon.id), level.titles.isEmpty {
            return [
                .message(
                    "\(icon.name) isn’t indexed", "Its menu is history, so Valet leaves it out of search and recents."
                ),
                .reveal(icon),
            ]
        }
        if level.titles.isEmpty, icon.menu == nil {
            return [.loading("Reading \(icon.name)’s menu… It opens for a moment, then closes.")]
        }
        let query = query.trimmingCharacters(in: .whitespaces)
        var rows: [Row] = []
        var lastWasDivider = true
        for (offset, entry) in level.entries.enumerated() {
            if entry.isSeparator {
                if query.isEmpty, !lastWasDivider { rows.append(.divider(offset)) }
                lastWasDivider = true
                continue
            }
            guard let title = entry.title else { continue }
            var hits = Set<Int>()
            if !query.isEmpty {
                guard let match = FuzzyMatch.match(title, query) else { continue }
                hits = match.hits
            }
            let titles = level.titles + [title]
            rows.append(.item(Item(
                icon: icon, titles: titles, entry: entry, key: SearchIndex.itemKey(icon.id, titles), hits: hits,
                local: true
            )))
            lastWasDivider = false
        }
        if case .divider = rows.last { rows.removeLast() }
        if rows.isEmpty { rows.append(.message("No matches", "Nothing in \(icon.name)’s menu matches “\(query)”.")) }
        return rows
    }

    // MARK: Keyboard

    func move(_ delta: Int) {
        confirming = nil
        guard !rows.isEmpty else { return }
        var index = selection ?? (delta > 0 ? -1 : rows.count)
        for _ in rows.indices {
            index = (index + delta + rows.count) % rows.count
            if rows[index].isSelectable {
                selection = index
                return
            }
        }
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index), rows[index].isSelectable, selection != index else { return }
        selection = index
        confirming = nil
    }

    /// Return. `showInMenuBar` (⌘Return) opens the app's icon instead of running the item.
    func activate(showInMenuBar: Bool = false) {
        guard let row = selectedRow else { return }
        switch row {
        case .icon(let icon, _):
            if showInMenuBar || !drill() { open(icon) }
        case .item(let item):
            if showInMenuBar { return open(item.icon) }
            if item.entry.children != nil { _ = drill(); return }
            // Quit, Delete, Sign Out and Reset need a second Return, so a mistyped search can't quit something.
            if item.isDestructive, confirming != item.key {
                confirming = item.key
                return
            }
            confirming = nil
            recordUse(item.key)
            onRun?(item)
        case .reveal(let icon):
            revealed.insert(icon.id)
            rebuild(keepingSelection: false)
        default:
            break
        }
    }

    /// → or Return on an app or submenu: go into its menu. Returns false for things without one (panels).
    @discardableResult
    func drill() -> Bool {
        guard let row = selectedRow else { return false }
        switch row {
        case .icon(let icon, _):
            guard icon.menuAvailability != .panel, icon.menuAvailability != .noResponse else { return false }
            stack.append(Level(icon: icon, titles: [], entries: icon.menu ?? []))
            enterLevel()
            if icon.menu == nil, !index.isPrivate(icon) { read(icon) }
            return true
        case .item(let item):
            guard let children = item.entry.children else { return false }
            stack.append(Level(icon: item.icon, titles: item.titles, entries: children))
            enterLevel()
            return true
        default:
            return false
        }
    }

    /// ←, or Delete with nothing typed: back out of a menu.
    @discardableResult
    func back() -> Bool {
        guard !stack.isEmpty else { return false }
        stack.removeLast()
        enterLevel()
        return true
    }

    /// Esc: cancel a confirmation, then clear the search, then back out, then close.
    func escape() {
        if confirming != nil {
            confirming = nil
        } else if !query.isEmpty {
            query = ""
        } else if !back() {
            onClose?()
        }
    }

    func togglePin() {
        // Items and icons can be pinned; section headers and messages can't.
        switch selectedRow {
        case .item, .icon: break
        default: return
        }
        guard let id = selectedRow?.id else { return }
        history.togglePin(id)
        store.save(history)
        rebuild(keepingSelection: true)
    }

    private func enterLevel() {
        confirming = nil
        if query.isEmpty { rebuild(keepingSelection: false) } else { query = "" }
    }

    private func open(_ icon: MenuBarIcon) {
        recordUse(SearchIndex.iconKey(icon.id))
        onOpen?(icon)
    }

    private func recordUse(_ key: String) {
        guard let candidate = index.candidate(forKey: key), !index.isPrivate(candidate.icon) || candidate.kind == .icon
        else { return }
        history.recordUse(key)
        store.save(history)
    }

    /// Reads a menu that only exists while open, then shows it here (or backs out if it turned out to be a panel).
    private func read(_ icon: MenuBarIcon) {
        guard reading != icon.id else { return }
        reading = icon.id
        Task {
            let result = await onRead?(icon)
            reading = nil
            guard let level = stack.last, level.icon.id == icon.id, level.titles.isEmpty else { return }
            if let result, let menu = result.menu {
                stack[stack.count - 1] = Level(icon: result, titles: [], entries: menu)
                rebuild(keepingSelection: false)
            } else {
                stack.removeLast()
                rebuild(keepingSelection: false)
            }
        }
    }
}
