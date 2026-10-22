import AppKit
import ValetCore

/// State behind the Valet panel: its rows, what's highlighted, and a drag in progress.
@MainActor
@Observable
final class ValetPanelModel {
    enum DropTarget: Equatable {
        /// Among the keepers, before the keeper at this index (excluding the one being dragged).
        case keepers(Int)
        case tucked
    }

    struct Drag: Equatable {
        var id: String
        var location: CGPoint
        var target: DropTarget?
    }

    var trusted = true
    var loaded = false
    /// Kept icons, as keepers, in order. Draggable.
    var keepers: [MenuBarIcon] = []
    /// Icons right of Valet (Apple's items). Always in the bar, so not draggable.
    var fixed: [MenuBarIcon] = []
    /// Tucked icons that aren't kept, in the real bar's order.
    var tucked: [MenuBarIcon] = []
    /// The palette's shortcut, shown on the Search row (e.g. "⌃⌥Space").
    var paletteShortcut = ""
    /// The row under the pointer or chosen with the keyboard.
    var highlighted: String?
    var drag: Drag?

    /// Row frames in the panel's coordinate space, reported by the view. Used for drops and to place menus.
    @ObservationIgnored var rowFrames: [String: CGRect] = [:]
    @ObservationIgnored var tuckedHeaderMinY: CGFloat = .infinity
    @ObservationIgnored var keepersHeaderMaxY: CGFloat = 0

    // Actions the controller handles.
    @ObservationIgnored var onActivate: ((MenuBarIcon) -> Void)?
    @ObservationIgnored var onHover: ((MenuBarIcon?) -> Void)?
    @ObservationIgnored var onSetKept: (([String]) -> Void)?
    @ObservationIgnored var onSearch: (() -> Void)?
    @ObservationIgnored var onSettings: (() -> Void)?
    @ObservationIgnored var onOpenPrivacySettings: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?

    func update(snapshot: MenuBarSnapshot, kept: [String]) {
        let sections = MenuBarSections(snapshot)
        let byID = Dictionary(snapshot.icons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        keepers = kept.compactMap { byID[$0] }
        fixed = sections.inBar.filter { !kept.contains($0.id) }
        tucked = sections.tucked.filter { !kept.contains($0.id) }
        loaded = true
    }

    var keptIDs: [String] { keepers.map(\.id) }

    /// Every row the keyboard can move through, top to bottom.
    var navigable: [MenuBarIcon] { keepers + fixed + tucked }

    func icon(_ id: String) -> MenuBarIcon? { navigable.first { $0.id == id } }

    func isDraggable(_ id: String) -> Bool {
        keepers.contains { $0.id == id } || tucked.contains { $0.id == id }
    }

    // MARK: Pointer and keyboard

    func hover(_ id: String?) {
        guard drag == nil, highlighted != id else { return }
        highlighted = id
        onHover?(id.flatMap(icon))
    }

    func moveHighlight(by delta: Int) {
        let rows = navigable
        guard !rows.isEmpty else { return }
        let current = highlighted.flatMap { id in rows.firstIndex { $0.id == id } }
        let next = current.map { ($0 + delta + rows.count) % rows.count } ?? (delta > 0 ? 0 : rows.count - 1)
        highlighted = rows[next].id
        onHover?(nil)
    }

    func activateHighlighted() {
        guard let id = highlighted, let icon = icon(id) else { return }
        onActivate?(icon)
    }

    /// Space: keep a tucked icon (at the end of the keepers), or tuck a keeper.
    func toggleKeepHighlighted() {
        guard let id = highlighted, isDraggable(id) else { return }
        let kept = keptIDs
        onSetKept?(kept.contains(id) ? kept.filter { $0 != id } : kept + [id])
    }

    // MARK: Dragging

    func dragChanged(_ id: String, to location: CGPoint) {
        if drag == nil { onHover?(nil) }
        drag = Drag(id: id, location: location, target: dropTarget(at: location.y, excluding: id))
    }

    func dragEnded() {
        guard let drag else { return }
        self.drag = nil
        var kept = keptIDs.filter { $0 != drag.id }
        switch drag.target {
        case .keepers(let index):
            kept.insert(drag.id, at: min(index, kept.count))
        case .tucked:
            break
        case nil:
            return
        }
        onSetKept?(kept)
    }

    /// Below the "Tucked Away" header tucks; anywhere above lands among the keepers, by row midpoints.
    func dropTarget(at y: CGFloat, excluding id: String) -> DropTarget {
        if y >= tuckedHeaderMinY { return .tucked }
        let others = keepers.filter { $0.id != id }
        let index = others.firstIndex { icon in
            guard let frame = rowFrames[icon.id] else { return false }
            return y < frame.midY
        }
        return .keepers(index ?? others.count)
    }

    /// Where to draw the insertion line for a drop among the keepers.
    func insertionLineY(for index: Int, excluding id: String) -> CGFloat {
        let frames = keepers.filter { $0.id != id }.compactMap { rowFrames[$0.id] }
        if frames.isEmpty { return keepersHeaderMaxY + 2 }
        return index < frames.count ? frames[index].minY : frames[frames.count - 1].maxY
    }
}
