import AppKit
import KeyboardShortcuts
import SwiftUI
import BellhopCore

/// The Bellhop panel: a menu-styled window under Bellhop's icon. It opens when the pointer rests on the icon, or on a
/// click. Each app's mirrored menu opens beside its row on hover, drawn by Bellhop (see `CascadeModel`).
@MainActor
final class BellhopPanelController: NSObject {
    let model = BellhopPanelModel()
    private let engine: MenuBarEngine
    private let system: LiveAccessibility
    private let keepers: KeeperController
    private let mirror: MenuMirror
    private let divider: DividerController
    private var panel: FloatingPanel?
    private var hosting: NSHostingView<BellhopPanelView>?
    private weak var statusItem: NSStatusItem?
    private var monitors: [Any] = []
    private(set) var snapshot: MenuBarSnapshot?
    /// Every new scan, for keepers.
    var onScan: ((MenuBarSnapshot) -> Void)?

    // Opening on hover over Bellhop's icon.
    private let iconTracker = HoverTracker()
    private var pendingOpen: DispatchWorkItem?
    /// Opened by resting on the icon, and the pointer hasn't gone into the panel yet: leaving closes it again.
    private var tentative = false
    private var tentativeWatch: Timer?
    private var outsideSince: Date?

    // App menus beside rows.
    private let cascade = CascadeController()
    private var pendingHover: DispatchWorkItem?

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
        model.onActivate = { [weak self] in self?.activate($0) }
        model.onHover = { [weak self] in self?.hovered($0) }
        model.onMenuKey = { [weak self] in self?.menuKey($0) ?? false }
        model.onSetKept = { ids in keepers.setKept(ids, iconPosition: divider.iconPosition) }
        model.onOpenPrivacySettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        model.onClose = { [weak self] in self?.close() }
        cascade.parentWindow = { [weak self] in self?.panel }
        cascade.rowFrame = { [weak self] in self?.screenFrame(of: $0) }
        cascade.onChoose = { [weak self] path in
            self?.close()
            mirror.run(path, confirm: false)
        }
    }

    var isOpen: Bool { panel?.isVisible == true }

    /// A click on Bellhop's icon. A click on a panel that only opened on hover keeps it open instead of closing it.
    func toggle(from item: NSStatusItem) {
        pendingOpen?.cancel()
        if isOpen, tentative {
            commit()
        } else if isOpen {
            close()
        } else {
            show(from: item)
        }
    }

    /// Opens the panel when the pointer rests on Bellhop's icon for a moment, so passing over the menu bar doesn't.
    func openOnHover(_ item: NSStatusItem) {
        guard let button = item.button else { return }
        iconTracker.onEnter = { [weak self, weak item] in
            guard let self, let item else { return }
            pendingOpen?.cancel()
            let open = DispatchWorkItem { [weak self, weak item] in
                guard let self, let item, !isOpen, NSEvent.pressedMouseButtons == 0,
                      item.button?.window?.frame.contains(NSEvent.mouseLocation) == true else { return }
                show(from: item, tentatively: true)
            }
            pendingOpen = open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: open)
        }
        iconTracker.onExit = { [weak self] in self?.pendingOpen?.cancel() }
        button.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: iconTracker
        ))
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

    private func show(from item: NSStatusItem, tentatively: Bool = false) {
        statusItem = item
        model.trusted = system.isTrusted
        model.paletteShortcut = KeyboardShortcuts.getShortcut(for: .togglePalette)?.description ?? ""
        model.highlighted = nil
        if let snapshot { model.update(snapshot: snapshot, kept: keepers.kept) }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        resize()
        panel.orderFrontRegardless()
        item.button?.highlight(true)
        installMonitors()
        // Opened on hover, the panel only takes the keyboard once you go into it, so typing elsewhere isn't caught.
        if tentatively { watchTentative() } else { commit() }

        guard system.isTrusted else { return }
        Task {
            guard let fresh = try? await engine.scan(SystemSnapshot.capture()) else { return }
            accept(fresh)
        }
    }

    /// The panel stays open like a menu from here: it takes the keyboard, and only a click elsewhere closes it.
    private func commit() {
        tentative = false
        tentativeWatch?.invalidate()
        tentativeWatch = nil
        panel?.makeKey()
    }

    /// Closes a panel opened on hover once the pointer has been away from the icon and panel for a moment.
    private func watchTentative() {
        tentative = true
        outsideSince = nil
        tentativeWatch?.invalidate()
        let watch = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTentative() }
        }
        RunLoop.main.add(watch, forMode: .common)
        tentativeWatch = watch
    }

    private func checkTentative() {
        let point = NSEvent.mouseLocation
        if panel?.frame.contains(point) == true {
            commit()
            model.hover(rowID(at: point))
        } else if statusItem?.button?.window?.frame.contains(point) == true {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date.now.timeIntervalSince(since) > 0.4 { close() }
        } else {
            outsideSince = .now
        }
    }

    func close() {
        pendingOpen?.cancel()
        tentative = false
        tentativeWatch?.invalidate()
        tentativeWatch = nil
        closeCascade()
        panel?.orderOut(nil)
        statusItem?.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        model.drag = nil
        model.highlighted = nil
    }

    private func makePanel() -> FloatingPanel {
        let hosting = NSHostingView(rootView: BellhopPanelView(model: model))
        let panel = FloatingPanel(content: hosting)
        self.hosting = hosting
        return panel
    }

    /// Fits the panel to its rows and hangs it under Bellhop's icon, like a menu.
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

    /// Clicks anywhere else close the panel, as with a menu. Clicks on Bellhop's icon go through its own toggle, and
    /// clicks in an app menu beside the panel choose from it.
    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { self.close() }
        }) {
            monitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]
        ) { event in
            let used = MainActor.assumeIsolated { self.handleClick(event) }
            return used ? nil : event
        }
        if let local { monitors.append(local) }
    }

    /// True if the click was in an app menu and is used up here.
    private func handleClick(_ event: NSEvent) -> Bool {
        if cascade.contains(event.window) {
            if event.type == .leftMouseUp { cascade.click(in: event.window) }
            return true
        }
        if event.type != .leftMouseUp, event.window !== panel, event.window !== statusItem?.button?.window {
            close()
        }
        return false
    }

    // MARK: Rows

    /// A click, →, or Return on a row.
    private func activate(_ icon: MenuBarIcon) {
        pendingHover?.cancel()
        if icon.menu?.isEmpty == false {
            if cascade.icon?.id != icon.id { openCascade(icon) }
            return
        }
        // A panel app, or a menu Bellhop hasn't read yet. Opening reads such a menu once (then it shows beside the
        // row), or presses the real icon and moves its panel under Bellhop's icon.
        closeCascade()
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
                if opened.menu?.isEmpty == false, isOpen {
                    replace(opened)
                    openCascade(opened)
                } else {
                    close()
                }
            } catch let error as BellhopError {
                MenuMirror.alert(error.message)
            } catch {
                MenuMirror.alert(error.localizedDescription)
            }
        }
    }

    /// Swaps in an icon whose menu was just read, so its row gets a chevron and its menu.
    private func replace(_ icon: MenuBarIcon) {
        guard var snapshot, let index = snapshot.icons.firstIndex(where: { $0.id == icon.id }) else { return }
        snapshot.icons[index] = icon
        self.snapshot = snapshot
        model.update(snapshot: snapshot, kept: keepers.kept)
    }

    /// Resting on a row opens its app's menu beside it, like a submenu; a row without a menu closes the open one.
    /// Menus that only exist while open aren't read on hover, since that flashes the real menu: those wait for a
    /// click. Nil (the keyboard moved, or a drag began) closes the menu.
    private func hovered(_ icon: MenuBarIcon?) {
        pendingHover?.cancel()
        guard let icon, model.drag == nil else { return closeCascade() }
        guard cascade.icon?.id != icon.id else { return }
        let open = DispatchWorkItem { [weak self] in
            guard let self, isOpen, model.drag == nil, NSEvent.pressedMouseButtons == 0 else { return }
            if icon.menu?.isEmpty == false { openCascade(icon) } else { closeCascade() }
        }
        pendingHover = open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: open)
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

    // MARK: App menus beside rows

    private func openCascade(_ icon: MenuBarIcon, highlightingFirst: Bool = false) {
        pendingHover?.cancel()
        model.highlighted = icon.id
        cascade.open(icon, highlightingFirst: highlightingFirst)
    }

    private func closeCascade() {
        pendingHover?.cancel()
        cascade.close()
    }

    /// Keys go to an open app menu. → or Return on a row with a menu opens it, with its first entry highlighted.
    private func menuKey(_ key: MenuKey) -> Bool {
        if !cascade.isOpen, key == .rightArrow || key == .enter {
            guard let id = model.highlighted, let icon = model.icon(id), icon.menu?.isEmpty == false else {
                return false
            }
            openCascade(icon, highlightingFirst: true)
            return true
        }
        return cascade.key(key)
    }
}

/// Receives the pointer entering and leaving Bellhop's icon.
private final class HoverTracker: NSResponder {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
