import AppKit
import KeyboardShortcuts
import SwiftUI
import ValetCore

/// The command palette, as approved in design/mocks: a search field, ranked rows, and a footer of key hints.
struct PaletteView: View {
    @Bindable var model: PaletteModel

    static let width: CGFloat = 680
    private static let rowHeight: CGFloat = 40
    private static let maxResultsHeight: CGFloat = 392

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider().opacity(0.6)
            results
            Divider().opacity(0.6)
            footer
        }
        .frame(width: Self.width)
    }

    // MARK: Search

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            if let level = model.currentLevel {
                HStack(spacing: 6) {
                    AppIconImage(icon: level.icon, size: 16)
                    Text(([level.icon.name] + level.titles).joined(separator: " › "))
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            PaletteSearchField(text: $model.query, placeholder: placeholder, model: model)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var placeholder: String {
        guard let level = model.currentLevel else { return "Search the menu bar" }
        return "Filter \(level.titles.last ?? level.icon.name)"
    }

    // MARK: Results

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, index: index).id(row.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: resultsHeight)
            .onChange(of: model.selection) { _, selection in
                guard let selection, model.rows.indices.contains(selection) else { return }
                proxy.scrollTo(model.rows[selection].id)
            }
        }
    }

    /// Grows with the rows up to the cap, so a short list makes a short palette.
    private var resultsHeight: CGFloat {
        let height = model.rows.reduce(CGFloat(12)) { total, row in
            switch row {
            case .section: total + 26
            case .divider: total + 11
            case .message, .loading: total + 58
            default: total + Self.rowHeight
            }
        }
        return min(Self.maxResultsHeight, height)
    }

    @ViewBuilder private func rowView(_ row: PaletteModel.Row, index: Int) -> some View {
        switch row {
        case .section(let title, let count):
            HStack {
                Text(title)
                Spacer()
                if let count { Text("\(count)") }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
        case .divider:
            Divider().padding(.horizontal, 10).padding(.vertical, 5)
        case .message(let title, let body):
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(body).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(.leading, 45)
            .padding(.vertical, 12)
        case .loading(let title):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(.leading, 18)
            .padding(.vertical, 18)
        case .icon(let icon, let hits):
            selectableRow(index: index) { selected in
                IconResultRow(icon: icon, hits: hits, selected: selected, pinned: isPinned(row))
            }
        case .item(let item):
            selectableRow(index: index) { selected in
                ItemResultRow(
                    item: item, selected: selected, confirming: model.confirming == item.key, pinned: isPinned(row)
                )
            }
        case .reveal(let icon):
            selectableRow(index: index) { selected in
                HStack(spacing: 11) {
                    AppIconImage(icon: icon, size: 24)
                    Text("Show \(icon.name)’s menu this once").foregroundStyle(selected ? .white : .primary)
                    Spacer()
                }
            }
        }
    }

    private func selectableRow<Content: View>(
        index: Int, @ViewBuilder content: (Bool) -> Content
    ) -> some View {
        let selected = model.selection == index
        let confirming = selected && {
            if case .item(let item) = model.rows[index] { return model.confirming == item.key }
            return false
        }()
        return content(selected)
            .font(.system(size: 14))
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(confirming ? Color.red : selected ? Color.accentColor : .clear)
            )
            .contentShape(Rectangle())
            .onHover { inside in if inside { model.select(index) } }
            .onTapGesture {
                model.select(index)
                model.activate()
            }
    }

    private func isPinned(_ row: PaletteModel.Row) -> Bool { model.history.isPinned(row.id) }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Text(hint)
                .foregroundStyle(warning ? Color.red : .secondary)
                .fontWeight(warning ? .medium : .regular)
                .lineLimit(1)
            Spacer(minLength: 8)
            ForEach(actions, id: \.label) { action in
                HStack(spacing: 4) {
                    Text(action.label)
                    ForEach(action.keys, id: \.self) { KeyCap(text: $0) }
                }
                .foregroundStyle(action.primary ? .primary : .secondary)
                .fontWeight(action.primary ? .medium : .regular)
            }
        }
        .font(.system(size: 12))
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 38)
    }

    private struct Action {
        var label: String
        var keys: [String]
        var primary = false
    }

    private var warning: Bool { model.confirming != nil }

    private var hint: String {
        switch model.selectedRow {
        case .item(let item):
            if model.confirming == item.key { return "\(item.titles.last ?? "This") can’t be undone" }
            if item.isDestructive { return "Asks before running" }
            return item.icon.isHidden ? "\(item.icon.name) is tucked away" : ""
        case .icon(let icon, _):
            switch icon.menuAvailability {
            case .panel: return "Opens a panel"
            case .noResponse: return "Doesn’t respond to Valet"
            case .onDemand where icon.menu == nil: return "Menu is read when you open it"
            default: return icon.isHidden ? "Tucked away" : ""
            }
        case .reveal:
            return "Shown this time only. It stays out of search."
        default:
            return ""
        }
    }

    private var actions: [Action] {
        switch model.selectedRow {
        case .item(let item):
            if model.confirming == item.key {
                return [Action(label: "Cancel", keys: ["esc"]),
                        Action(label: item.titles.last?.split(separator: " ").first.map(String.init) ?? "Run",
                               keys: ["↩"], primary: true)]
            }
            if item.entry.children != nil { return [Action(label: "Open", keys: ["→"], primary: true)] }
            return [
                Action(label: model.history.isPinned(item.key) ? "Unpin" : "Pin", keys: ["⌘", "P"]),
                Action(label: "Show in Menu Bar", keys: ["⌘", "↩"]),
                Action(label: "Run", keys: ["↩"], primary: true),
            ]
        case .icon(let icon, _):
            let hasMenu = icon.menuAvailability != .panel && icon.menuAvailability != .noResponse
            return hasMenu
                ? [
                    Action(label: "Show in Menu Bar", keys: ["⌘", "↩"]),
                    Action(label: "Open Menu", keys: ["↩"], primary: true),
                ]
                : [Action(label: "Open", keys: ["↩"], primary: true)]
        case .reveal:
            return [Action(label: "Show", keys: ["↩"], primary: true)]
        default:
            return [Action(label: "Close", keys: ["esc"])]
        }
    }
}

// MARK: Rows

private struct IconResultRow: View {
    let icon: MenuBarIcon
    let hits: Set<Int>
    let selected: Bool
    let pinned: Bool

    var body: some View {
        HStack(spacing: 11) {
            AppIconImage(icon: icon, size: 24)
            Highlighted(text: icon.name, hits: hits, offset: 0, selected: selected)
            Spacer(minLength: 8)
            if pinned { PinGlyph(selected: selected) }
            if let status = icon.statusText {
                Text(status).monospacedDigit().foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
            }
            if icon.menuAvailability != .panel, icon.menuAvailability != .noResponse {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? .white.opacity(0.8) : Color(nsColor: .tertiaryLabelColor))
            }
        }
        .foregroundStyle(selected ? .white : .primary)
    }
}

private struct ItemResultRow: View {
    let item: PaletteModel.Item
    let selected: Bool
    let confirming: Bool
    let pinned: Bool

    var body: some View {
        HStack(spacing: 11) {
            if item.local {
                // Inside a menu the breadcrumb names the app, so the icon's column holds the checkmark.
                Text(item.entry.mark == nil ? "" : "✓")
                    .frame(width: 24)
                    .foregroundStyle(selected ? .white : Color.accentColor)
            } else {
                AppIconImage(icon: item.icon, size: 24)
            }
            title.lineLimit(1)
            Spacer(minLength: 8)
            if confirming {
                Text("Press ↩ again").foregroundStyle(.white.opacity(0.9))
            } else {
                if pinned { PinGlyph(selected: selected) }
                if let shortcut = item.entry.shortcut {
                    Text(shortcut)
                        .tracking(1)
                        .foregroundStyle(selected ? .white.opacity(0.8) : Color(nsColor: .tertiaryLabelColor))
                }
                if item.entry.children != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? .white.opacity(0.8) : Color(nsColor: .tertiaryLabelColor))
                }
            }
        }
        .foregroundStyle(selected ? .white : item.entry.enabled ? .primary : Color(nsColor: .tertiaryLabelColor))
    }

    /// "Dropbox › Snooze Notifications › " muted, then the item's own title, with matched letters in bold.
    private var title: Text {
        let last = item.titles.last ?? ""
        if item.local {
            return mark + Highlighted.text(last, hits: item.hits, offset: 0)
        }
        let prefix = MenuPaths.join([item.icon.name] + item.titles.dropLast()) + MenuPaths.separator
        let muted = Highlighted.text(prefix, hits: item.hits, offset: 0)
            .foregroundColor(selected ? .white.opacity(0.75) : .secondary)
        return muted + mark + Highlighted.text(last, hits: item.hits, offset: prefix.count)
    }

    private var mark: Text {
        guard !item.local, item.entry.mark != nil else { return Text("") }
        return Text("✓ ").foregroundColor(selected ? .white : .accentColor)
    }
}

/// Text with the matched characters in bold.
private struct Highlighted: View {
    let text: String
    let hits: Set<Int>
    let offset: Int
    let selected: Bool

    var body: some View { Self.text(text, hits: hits, offset: offset) }

    static func text(_ string: String, hits: Set<Int>, offset: Int) -> Text {
        var attributed = AttributedString(string)
        for (index, character) in string.enumerated() where hits.contains(offset + index) {
            let start = attributed.index(attributed.startIndex, offsetByCharacters: index)
            let end = attributed.index(start, offsetByCharacters: 1)
            attributed[start..<end].font = .system(size: 14, weight: .bold)
            _ = character
        }
        return Text(attributed)
    }
}

private struct PinGlyph: View {
    let selected: Bool

    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 10))
            .rotationEffect(.degrees(45))
            .foregroundStyle(selected ? .white.opacity(0.8) : Color(nsColor: .tertiaryLabelColor))
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 4)
            .frame(minWidth: 20, minHeight: 18)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct AppIconImage: View {
    let icon: MenuBarIcon
    let size: CGFloat

    var body: some View {
        if let image = AppIcons.image(for: icon) {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size / 4).fill(.quaternary).frame(width: size, height: size)
        }
    }
}

// MARK: Search field

/// A borderless native text field, so arrow keys, Return and Esc can be read exactly (including "← only at the
/// start of the text") while typing still feels like any Mac text field.
struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let model: PaletteModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 21)
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        context.coordinator.parent = self
        if field.window?.firstResponder !== field.currentEditor() {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteSearchField

        init(parent: PaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let model = parent.model
            let caret = textView.selectedRange()
            let atStart = caret.location == 0 && caret.length == 0
            let atEnd = caret.location == textView.string.count && caret.length == 0
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                model.move(-1)
            case #selector(NSResponder.moveDown(_:)):
                model.move(1)
            case #selector(NSResponder.insertNewline(_:)):
                model.activate(showInMenuBar: NSApp.currentEvent?.modifierFlags.contains(.command) == true)
            case #selector(NSResponder.cancelOperation(_:)):
                model.escape()
            case #selector(NSResponder.moveRight(_:)) where atEnd:
                return model.drill()
            case #selector(NSResponder.moveLeft(_:)) where atStart:
                return model.back()
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty:
                return model.back()
            default:
                return false
            }
            return true
        }
    }
}
