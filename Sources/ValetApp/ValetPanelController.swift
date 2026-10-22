import AppKit
import KeyboardShortcuts
import SwiftUI
import ValetCore

/// The Valet panel: a menu-styled window under Valet's icon. It's Valet's own window rather than a native menu so
/// icons can be dragged in it, but each app's mirrored menu still opens as a real menu beside its row.
@MainActor
final class ValetPanelController: NSObject {
    let model = ValetPanelModel()
    private let engine: MenuBarEngine
    private let system: LiveAccessibility
    private let keepers: KeeperController
    private let mirror: MenuMirror
    private let divider: DividerController
    private var panel: FloatingPanel?
    private var hosting: NSHostingView<ValetPanelView>?
    private weak var statusItem: NSStatusItem?
    private var monitors: [Any] = []
    private(set) var snapshot: MenuBarSnapshot?
    /// Every new scan, for keepers.
    var onScan: ((MenuBarSnapshot) -> Void)?

    // The mirrored menu open beside a row, and what to do when it closes.
    private var submenuFor: String?
    private var submenu: NSMenu?
    private var nextSubmenu: MenuBarIcon?
    private var pendingHover: DispatchWorkItem?
    private var actionRan = false

    init(
        engine: MenuBarEngine, system: LiveAccessibility, keepers: KeeperController, mirror: MenuMirror,
        divider: DividerController
    ) {
        self.engine = engine
        self.system = system
        self.keepers = keepers
        self.mirror = mirror
        self.divider = divider
        super.init()
        mirror.onAction = { [weak self] in self?.actionRan = true }
        model.onActivate = { [weak self] in self?.activate($0) }
        model.onHover = { [weak self] in self?.hovered($0) }
        model.onSetKept = { ids in keepers.setKept(ids, iconPosition: divider.iconPosition) }
        model.onOpenPrivacySettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        model.onClose = { [weak self] in self?.close() }
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(from item: NSStatusItem) {
        if isOpen { close() } else { show(from: item) }
    }

    /// Takes a scan made elsewhere (at launch) or by this panel, and refreshes the rows.
    func accept(_ fresh: MenuBarSnapshot) {
        receive(fresh)
        onScan?(fresh)
    }

    /// Takes a scan made elsewhere (the palette) without passing it on again.
    func receive(_ fresh: MenuBarSnapshot) {
        snapshot = fresh
        model.update(snapshot: fresh, kept: keepers.kept)
        resize()
    }

    /// Keepers changed (a drag, Space, or anywhere else): redraw the sections.
    func keptChanged() {
        guard let snapshot else { return }
        model.update(snapshot: snapshot, kept: keepers.kept)
        resize()
    }

    // MARK: Showing and closing

    private func show(from item: NSStatusItem) {
        statusItem = item
        model.trusted = system.isTrusted
        model.paletteShortcut = KeyboardShortcuts.getShortcut(for: .togglePalette)?.description ?? ""
        model.highlighted = nil
        if let snapshot { model.update(snapshot: snapshot, kept: keepers.kept) }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        resize()
        panel.orderFrontRegardless()
        panel.makeKey()
        item.button?.highlight(true)
        installMonitors()

        guard system.isTrusted else { return }
        Task {
            guard let fresh = try? await engine.scan(SystemSnapshot.capture()) else { return }
            accept(fresh)
        }
    }

    func close() {
        pendingHover?.cancel()
        panel?.orderOut(nil)
        statusItem?.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        model.drag = nil
        model.highlighted = nil
    }

    private func makePanel() -> FloatingPanel {
        let hosting = NSHostingView(rootView: ValetPanelView(model: model))
        let panel = FloatingPanel(content: hosting)
        self.hosting = hosting
        return panel
    }

    /// Fits the panel to its rows and hangs it under Valet's icon, like a menu.
    private func resize() {
        guard let panel, let hosting, let button = statusItem?.button, let iconWindow = button.window,
              let screen = iconWindow.screen else { return }
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let x = min(max(iconWindow.frame.minX - 6, visible.minX + 6), visible.maxX - size.width - 6)
        let top = iconWindow.frame.minY - 4
        let height = min(size.height, top - visible.minY - 6)
        panel.setFrame(NSRect(x: x, y: top - height, width: size.width, height: height), display: true)
    }

    /// Clicks anywhere else close the panel, as with a menu. Clicks on Valet's icon go through its own toggle.
    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { self.close() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
            MainActor.assumeIsolated {
                if event.window !== self.panel, event.window !== self.statusItem?.button?.window { self.close() }
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    // MARK: Rows

    private func activate(_ icon: MenuBarIcon) {
        if mirror.menu(for: icon) != nil {
            presentSubmenu(for: icon)
            return
        }
        // A panel app, or a menu Valet hasn't read yet. Opening reads such a menu once (then it shows beside the
        // row), or presses the real icon and moves its panel under Valet's icon.
        guard let iconWindow = statusItem?.button?.window, let screen = iconWindow.screen else { return }
        let x = Double(iconWindow.frame.minX)
        let screenMaxX = Double(screen.frame.maxX)
        let wasPanel = icon.menuAvailability == .panel
        if wasPanel { close() }
        Task {
            do {
                let opened = try await engine.open(
                    icon.name, alignTo: x, screenMaxX: screenMaxX, env: SystemSnapshot.capture()
                )
                if mirror.menu(for: opened) != nil, isOpen {
                    replace(opened)
                    presentSubmenu(for: opened)
                } else {
                    close()
                }
            } catch let error as ValetError {
                MenuMirror.alert(error.message)
            } catch {
                MenuMirror.alert(error.localizedDescription)
            }
        }
    }

    /// Swaps in an icon whose menu was just read, so its row gets a chevron and its mirror.
    private func replace(_ icon: MenuBarIcon) {
        guard var snapshot, let index = snapshot.icons.firstIndex(where: { $0.id == icon.id }) else { return }
        snapshot.icons[index] = icon
        self.snapshot = snapshot
        model.update(snapshot: snapshot, kept: keepers.kept)
    }

    /// Hovering a row with a mirrored menu opens it after a short pause, like a submenu.
    /// Hovering only highlights. An app's menu opens on click, → or Return: a real menu captures the mouse, so
    /// opening one on hover made those rows impossible to drag. Once a menu is open, moving to another row
    /// switches menus, like a menu bar.
    private func hovered(_ icon: MenuBarIcon?) {
        pendingHover?.cancel()
    }

    // MARK: Mirrored menus beside rows

    /// Pops the app's real menu, mirrored, beside its row. A native menu takes over event handling while it's
    /// open, so a timer watches the pointer: moving onto another row closes this menu and opens that one.
    private func presentSubmenu(for icon: MenuBarIcon) {
        guard submenuFor == nil, let panel, let menu = mirror.menu(for: icon),
              let row = screenFrame(of: icon.id), let screen = panel.screen else { return }
        submenuFor = icon.id
        nextSubmenu = nil
        actionRan = false
        model.highlighted = icon.id

        let width = menu.size.width
        let fitsRight = panel.frame.maxX + width + 4 < screen.visibleFrame.maxX
        let origin = NSPoint(x: fitsRight ? panel.frame.maxX - 2 : panel.frame.minX - width + 2, y: row.maxY + 5)

        submenu = menu
        let watcher = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchPointer() }
        }
        RunLoop.main.add(watcher, forMode: .common)
        menu.popUp(positioning: nil, at: origin, in: nil)
        watcher.invalidate()
        submenu = nil
        submenuFor = nil

        if actionRan {
            close()
        } else if let next = nextSubmenu {
            nextSubmenu = nil
            model.highlighted = next.id
            DispatchQueue.main.async { [weak self] in self?.presentSubmenu(for: next) }
        }
    }

    private var pointerRow: (id: String, since: Date)?

    private func watchPointer() {
        guard let panel, panel.frame.contains(NSEvent.mouseLocation),
              let id = rowID(at: NSEvent.mouseLocation), id != submenuFor else {
            pointerRow = nil
            return
        }
        if pointerRow?.id != id { pointerRow = (id, .now) }
        // A short dwell, so passing over rows on the way into the menu doesn't switch it.
        guard let dwell = pointerRow, Date.now.timeIntervalSince(dwell.since) > 0.12 else { return }
        pointerRow = nil
        model.highlighted = id
        nextSubmenu = model.icon(id).flatMap { mirror.menu(for: $0) != nil ? $0 : nil }
        submenu?.cancelTracking()
    }

    private func screenFrame(of id: String) -> NSRect? {
        guard let panel, let hosting, let frame = model.rowFrames[id] else { return nil }
        return panel.convertToScreen(hosting.convert(frame, to: nil))
    }

    private func rowID(at point: NSPoint) -> String? {
        guard let panel, let hosting else { return nil }
        let local = hosting.convert(panel.convertPoint(fromScreen: point), from: nil)
        return model.rowFrames.first { $0.value.contains(local) }?.key
    }
}
