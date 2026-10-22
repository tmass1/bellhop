import SwiftUI
import ValetCore

/// The mirrored app menus beside the Valet panel. Valet draws them itself, menu-styled, rather than opening real
/// menus: a real menu captures the mouse while it's open, so it couldn't open on hover without making the panel's
/// rows impossible to drag.
@MainActor
@Observable
final class CascadeModel {
    struct Level: Identifiable {
        var icon: MenuBarIcon
        /// Titles from the app's menu down to this level; empty for the app's own menu.
        var titles: [String]
        var entries: [MenuEntry]
        var highlighted: Int?

        var id: String { ([icon.id] + titles).joined(separator: "›") }
    }

    var levels: [Level] = [] {
        didSet { if levels.map(\.id) != oldValue.map(\.id) { onLevelsChange?() } }
    }
    /// Entry frames per level, in each level's own view, for hit-testing the pointer and placing submenus.
    @ObservationIgnored var entryFrames: [Int: [Int: CGRect]] = [:]
    /// A level opened or closed, so the controller can add or remove its window.
    @ObservationIgnored var onLevelsChange: (() -> Void)?

    var isOpen: Bool { !levels.isEmpty }
    var icon: MenuBarIcon? { levels.first?.icon }
    /// The deepest level with a highlighted entry: where the arrow keys act.
    var focusDepth: Int? { levels.lastIndex { $0.highlighted != nil } }

    func open(_ icon: MenuBarIcon) {
        entryFrames = [:]
        levels = [Level(icon: icon, titles: [], entries: icon.menu ?? [], highlighted: nil)]
    }

    func close(from depth: Int = 0) {
        guard depth < levels.count else { return }
        entryFrames = entryFrames.filter { $0.key < depth }
        levels.removeSubrange(depth...)
    }

    /// Opens the submenu of the highlighted entry at `depth`, if it has one and it isn't open already.
    @discardableResult
    func openChild(of depth: Int) -> Bool {
        guard levels.indices.contains(depth), let index = levels[depth].highlighted,
              let children = levels[depth].entries[index].children, let title = levels[depth].entries[index].title
        else { return false }
        let titles = levels[depth].titles + [title]
        if levels.indices.contains(depth + 1), levels[depth + 1].titles == titles { return true }
        close(from: depth + 1)
        levels.append(Level(icon: levels[depth].icon, titles: titles, entries: children))
        return true
    }

    /// Moves the highlight at `depth`, skipping separators and disabled items, and closes anything deeper.
    func move(_ delta: Int, at depth: Int) {
        guard levels.indices.contains(depth) else { return }
        let entries = levels[depth].entries
        var index = levels[depth].highlighted ?? (delta > 0 ? -1 : entries.count)
        for _ in entries.indices {
            index = (index + delta + entries.count) % entries.count
            if isChoosable(entries[index]) {
                levels[depth].highlighted = index
                close(from: depth + 1)
                return
            }
        }
    }

    func isChoosable(_ entry: MenuEntry) -> Bool {
        !entry.isSeparator && entry.title != nil && entry.enabled
    }

    func entry(depth: Int, index: Int) -> MenuEntry? {
        guard levels.indices.contains(depth), levels[depth].entries.indices.contains(index) else { return nil }
        return levels[depth].entries[index]
    }

    /// The menu path of an entry, e.g. "Mark › Settings…", for running it.
    func path(depth: Int, index: Int) -> String? {
        guard let title = entry(depth: depth, index: index)?.title else { return nil }
        return MenuPaths.join([levels[depth].icon.name] + levels[depth].titles + [title])
    }

    /// The choosable entry under a point in a level's view, if any.
    func index(atDepth depth: Int, point: CGPoint) -> Int? {
        guard let index = entryFrames[depth]?.first(where: { $0.value.contains(point) })?.key,
              let entry = entry(depth: depth, index: index), isChoosable(entry) else { return nil }
        return index
    }
}

/// Keys the Valet panel passes to an open app menu first.
enum MenuKey {
    case upArrow, downArrow, leftArrow, rightArrow, enter, escape
}

/// One level of the cascade, styled like a macOS menu.
struct CascadeLevelView: View {
    let model: CascadeModel
    let depth: Int

    static let space = "cascade-level"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.levels.indices.contains(depth) {
                let level = model.levels[depth]
                ForEach(Array(level.entries.enumerated()), id: \.offset) { index, entry in
                    if entry.isSeparator || entry.title == nil {
                        Divider().padding(.horizontal, 9).padding(.vertical, 5)
                    } else {
                        CascadeRow(entry: entry, highlighted: level.highlighted == index)
                            .background(GeometryReader { geometry in
                                Color.clear.preference(
                                    key: EntryFrameKey.self, value: [index: geometry.frame(in: .named(Self.space))]
                                )
                            })
                    }
                }
            }
        }
        .padding(5)
        .fixedSize()
        .coordinateSpace(.named(Self.space))
        .onPreferenceChange(EntryFrameKey.self) { frames in
            MainActor.assumeIsolated { model.entryFrames[depth] = frames }
        }
    }
}

private struct CascadeRow: View {
    let entry: MenuEntry
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.mark == nil ? "" : "✓")
                .font(.system(size: 12))
                .frame(width: 12)
            Text(entry.title ?? "")
                .lineLimit(1)
            Spacer(minLength: 24)
            if let shortcut = entry.shortcut {
                Text(shortcut).tracking(0.5).foregroundStyle(highlighted ? .white.opacity(0.85) : .secondary)
            }
            if entry.children != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(highlighted ? .white.opacity(0.85) : .secondary)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(highlighted ? .white : entry.enabled ? .primary : Color(nsColor: .tertiaryLabelColor))
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(minWidth: 200, minHeight: 22, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(highlighted ? Color.accentColor : .clear))
    }
}

private struct EntryFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
