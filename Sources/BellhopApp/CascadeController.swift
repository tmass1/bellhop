import AppKit
import SwiftUI
import BellhopCore

/// Shows an app's mirrored menu beside its row in the Bellhop panel, with nested submenus cascading out of it. Each
/// level is its own window. They never take the keyboard: the panel passes arrows, Return and Esc on.
@MainActor
final class CascadeController {
    private struct LevelWindow {
        let panel: FloatingPanel
        let hosting: NSHostingView<CascadeLevelView>
        var id: String
    }

    private struct Dwell {
        let depth: Int
        let index: Int?
        let since: Date
        var done = false
    }

    private let model = CascadeModel()
    private var windows: [LevelWindow] = []
    private var opensLeft = false
    private var pointerWatch: Timer?
    private var lastPointer: NSPoint?
    private var dwell: Dwell?

    /// The Bellhop panel, which the first level hangs beside.
    var parentWindow: (() -> NSWindow?)?
    /// A row's frame on screen, which the first level lines up with.
    var rowFrame: ((String) -> NSRect?)?
    /// An entry was chosen: its menu path, e.g. "Mark › Settings…".
    var onChoose: ((String) -> Void)?

    init() {
        model.onLevelsChange = { [weak self] in self?.layout() }
    }

    var isOpen: Bool { model.isOpen }
    var icon: MenuBarIcon? { model.icon }

    func contains(_ window: NSWindow?) -> Bool {
        windows.contains { $0.panel === window }
    }

    func open(_ icon: MenuBarIcon, highlightingFirst: Bool = false) {
        dwell = nil
        lastPointer = NSEvent.mouseLocation
        model.open(icon)
        if highlightingFirst { model.move(1, at: 0) }
        guard pointerWatch == nil else { return }
        let watch = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchPointer() }
        }
        RunLoop.main.add(watch, forMode: .common)
        pointerWatch = watch
    }

    func close() {
        pointerWatch?.invalidate()
        pointerWatch = nil
        dwell = nil
        model.close()
    }

    /// A mouse-up in one of the levels: runs the entry under the pointer, or opens its submenu.
    func click(in window: NSWindow?) {
        guard let depth = windows.firstIndex(where: { $0.panel === window }),
              let index = entryIndex(atDepth: depth, point: NSEvent.mouseLocation) else { return }
        model.levels[depth].highlighted = index
        choose(depth: depth, index: index)
    }

    /// Arrows, Return and Esc. False hands the key back to the panel.
    func key(_ key: MenuKey) -> Bool {
        guard model.isOpen else { return false }
        lastPointer = NSEvent.mouseLocation
        dwell = nil
        let depth = model.focusDepth
        switch key {
        case .upArrow, .downArrow:
            guard let depth else { return false }
            model.move(key == .downArrow ? 1 : -1, at: depth)
        case .rightArrow, .enter:
            guard let depth else {
                model.move(1, at: 0)
                return true
            }
            guard let index = model.levels[depth].highlighted else { return true }
            if model.entry(depth: depth, index: index)?.children != nil {
                model.openChild(of: depth)
                model.move(1, at: depth + 1)
            } else if key == .enter {
                choose(depth: depth, index: index)
            }
        case .leftArrow:
            guard let depth else { return false }
            if depth == 0 { close() } else { model.close(from: depth) }
        case .escape:
            close()
        }
        return true
    }

    private func choose(depth: Int, index: Int) {
        guard let entry = model.entry(depth: depth, index: index) else { return }
        if entry.children != nil {
            model.openChild(of: depth)
        } else if let path = model.path(depth: depth, index: index) {
            onChoose?(path)
        }
    }

    // MARK: Windows

    /// Adds or removes a window per open level, placing each new one beside the row or entry it came from.
    private func layout() {
        while windows.count > model.levels.count {
            windows.removeLast().panel.orderOut(nil)
        }
        for depth in model.levels.indices {
            let id = model.levels[depth].id
            if windows.indices.contains(depth) {
                guard windows[depth].id != id else { continue }
                windows[depth].id = id
                // Setting the root view again redraws it now, so it measures the new level's entries.
                windows[depth].hosting.rootView = CascadeLevelView(model: model, depth: depth)
            } else {
                let hosting = NSHostingView(rootView: CascadeLevelView(model: model, depth: depth))
                let panel = FloatingPanel(content: hosting)
                panel.takesKey = false
                windows.append(LevelWindow(panel: panel, hosting: hosting, id: id))
            }
            place(depth)
        }
    }

    private func place(_ depth: Int) {
        let window = windows[depth]
        guard let parent = depth == 0 ? parentWindow?() : windows[depth - 1].panel, let screen = parent.screen
        else { return }
        let anchor = anchorFrame(forDepth: depth)
            ?? NSRect(x: parent.frame.minX, y: parent.frame.maxY - 27, width: 0, height: 22)
        window.hosting.layoutSubtreeIfNeeded()
        let size = window.hosting.fittingSize
        let visible = screen.visibleFrame
        let right = parent.frame.maxX - 2
        let left = parent.frame.minX - size.width + 2
        if depth == 0 { opensLeft = right + size.width > visible.maxX }
        // Nested menus keep going the same way until they run out of room.
        var x = opensLeft ? left : right
        if x + size.width > visible.maxX { x = left } else if x < visible.minX { x = right }
        // The first entry lines up with the row or entry it came from, as with a native submenu.
        var top = min(anchor.maxY + 5, visible.maxY)
        if top - size.height < visible.minY { top = min(visible.minY + size.height, visible.maxY) }
        window.panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        window.panel.orderFront(nil)
    }

    /// The screen frame of what a level hangs from: the app's row for the first level, else its parent's entry.
    private func anchorFrame(forDepth depth: Int) -> NSRect? {
        guard depth > 0 else { return model.icon.flatMap { rowFrame?($0.id) } }
        let parent = windows[depth - 1]
        guard let index = model.levels[depth - 1].highlighted,
              let frame = model.entryFrames[depth - 1]?[index] else { return nil }
        return parent.panel.convertToScreen(parent.hosting.convert(frame, to: nil))
    }

    // MARK: Pointer

    /// Highlights the entry under the pointer. Resting on one opens its submenu or closes another's, after a short
    /// pause so cutting across entries on the way into a submenu doesn't switch it.
    private func watchPointer() {
        let point = NSEvent.mouseLocation
        if point != lastPointer {
            lastPointer = point
            if let depth = windows.lastIndex(where: { $0.panel.frame.contains(point) }),
               model.levels.indices.contains(depth) {
                let index = entryIndex(atDepth: depth, point: point)
                model.levels[depth].highlighted = index
                if dwell?.depth != depth || dwell?.index != index {
                    dwell = Dwell(depth: depth, index: index, since: .now)
                }
            }
        }
        guard let pending = dwell, !pending.done, Date.now.timeIntervalSince(pending.since) > 0.12 else { return }
        dwell?.done = true
        guard model.levels.indices.contains(pending.depth),
              model.levels[pending.depth].highlighted == pending.index else { return }
        if !model.openChild(of: pending.depth) { model.close(from: pending.depth + 1) }
    }

    private func entryIndex(atDepth depth: Int, point: NSPoint) -> Int? {
        let window = windows[depth]
        let local = window.hosting.convert(window.panel.convertPoint(fromScreen: point), from: nil)
        return model.index(atDepth: depth, point: local)
    }
}
