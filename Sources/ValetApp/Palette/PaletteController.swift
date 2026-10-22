import AppKit
import KeyboardShortcuts
import os
import SwiftUI
import ValetCore

extension KeyboardShortcuts.Name {
    /// ⌃⌥Space is a placeholder: it avoids Spotlight (⌘Space) and Raycast (⌥Space).
    static let togglePalette = Self("togglePalette", default: .init(.space, modifiers: [.control, .option]))
}

/// The command palette: a glass panel in the top third of the screen you're on. It opens instantly with the last
/// scan, then refreshes in place. The app you're in keeps focus.
@MainActor
final class PaletteController {
    let model = PaletteModel()
    private let engine: MenuBarEngine
    private let system: LiveAccessibility
    private let mirror: MenuMirror
    private var panel: FloatingPanel?
    private var hosting: NSHostingView<PaletteView>?
    private var monitors: [Any] = []
    private var snapshot: MenuBarSnapshot?
    private var kept: () -> [String]
    /// Every new scan, for keepers and the Valet panel.
    var onScan: ((MenuBarSnapshot) -> Void)?
    /// Where panels opened from here should go: the left edge of Valet's icon and its screen's right edge.
    var anchor: (() -> (x: Double, screenMaxX: Double)?)?
    private let log = Logger(subsystem: "com.tommymassaro.valet", category: "palette")

    init(engine: MenuBarEngine, system: LiveAccessibility, mirror: MenuMirror, kept: @escaping () -> [String]) {
        self.engine = engine
        self.system = system
        self.mirror = mirror
        self.kept = kept
        model.onClose = { [weak self] in self?.close() }
        model.onRun = { [weak self] in self?.run($0) }
        model.onOpen = { [weak self] in self?.open($0) }
        model.onRead = { [weak self] icon in await self?.read(icon) }
        KeyboardShortcuts.onKeyDown(for: .togglePalette) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() {
        if isOpen { close() } else { show() }
    }

    /// Takes a scan made anywhere in the app, so the palette always opens with the latest one.
    func accept(_ fresh: MenuBarSnapshot) {
        snapshot = fresh
        if isOpen {
            model.update(snapshot: fresh, kept: kept())
            resize()
        } else if panel == nil {
            prepare()
        }
    }

    /// Builds the window and lays out its first rows ahead of time, hidden, so the hotkey only has to show it.
    func prepare() {
        guard panel == nil else { return }
        if let snapshot { model.update(snapshot: snapshot, kept: kept()) }
        panel = makePanel()
        resize(placing: true)
        hosting?.layoutSubtreeIfNeeded()
    }

    // MARK: Showing

    func show(query: String? = nil) {
        let start = ContinuousClock.now
        if let snapshot { model.update(snapshot: snapshot, kept: kept()) }
        model.reset()
        if let query { model.query = query }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        resize(placing: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        installMonitors()
        log.notice("palette shown in \(Self.ms(since: start), privacy: .public) ms")

        // Refresh in the background; rows update in place.
        guard system.isTrusted else { return }
        Task {
            guard let fresh = try? await engine.scan(SystemSnapshot.capture()) else { return }
            accept(fresh)
            onScan?(fresh)
            log.notice("palette refreshed after \(Self.ms(since: start), privacy: .public) ms")
        }
    }

    func close() {
        panel?.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func makePanel() -> FloatingPanel {
        let hosting = NSHostingView(rootView: PaletteView(model: model))
        let panel = FloatingPanel(content: hosting, cornerRadius: 22, glass: true)
        panel.onResignKey = { [weak self] in self?.close() }
        self.hosting = hosting
        return panel
    }

    /// Fits the panel to its rows. When opening, it goes in the top third of the screen with the pointer, centered.
    private func resize(placing: Bool = false) {
        guard let panel, let hosting else { return }
        let size = hosting.fittingSize
        if placing {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            guard let visible = screen?.visibleFrame else { return }
            let top = visible.maxY - visible.height * 0.18
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: top - size.height,
                                  width: size.width, height: size.height), display: true)
        } else {
            // Keep the top edge where it is, like Spotlight, as the list grows or shrinks.
            let top = panel.frame.maxY
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                           display: true)
        }
    }

    /// Clicks outside close it; ⌘P pins. (Arrows, Return and Esc are handled by the search field.)
    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { self.close() }
        }) {
            monitors.append(global)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            guard command, event.charactersIgnoringModifiers == "p" else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard self.isOpen else { return false }
                self.model.togglePin()
                return true
            }
            return handled ? nil : event
        }) {
            monitors.append(keys)
        }
    }

    // MARK: Running

    private func run(_ item: PaletteModel.Item) {
        close()
        // The palette already asked twice for destructive items, so confirm is true here.
        Task {
            do {
                _ = try await engine.run(item.path, confirm: true, env: SystemSnapshot.capture())
            } catch let error as ValetError {
                MenuMirror.alert(error.message)
            } catch {
                MenuMirror.alert(error.localizedDescription)
            }
        }
    }

    /// Opens an icon like clicking it in the Valet panel: panels open under Valet's icon, menus are mirrored there.
    private func open(_ icon: MenuBarIcon) {
        close()
        guard let anchor = anchor?() else { return }
        Task {
            do {
                let opened = try await engine.open(
                    icon.name, alignTo: anchor.x, screenMaxX: anchor.screenMaxX, env: SystemSnapshot.capture()
                )
                if let menu = mirror.menu(for: opened) {
                    menu.popUp(positioning: nil, at: NSPoint(x: anchor.x, y: anchorTop()), in: nil)
                }
            } catch let error as ValetError {
                MenuMirror.alert(error.message)
            } catch {
                MenuMirror.alert(error.localizedDescription)
            }
        }
    }

    private func anchorTop() -> Double {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        return Double((screen?.visibleFrame.maxY ?? 0) - 4)
    }

    /// Reads a menu that only exists while open. Nil if the icon turned out to be a panel.
    private func read(_ icon: MenuBarIcon) async -> MenuBarIcon? {
        do {
            let loaded = try await engine.loadMenu(icon.name, env: SystemSnapshot.capture())
            return loaded.menu == nil ? nil : loaded
        } catch {
            return nil
        }
    }

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let duration = ContinuousClock.now - start
        return Int(Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000)
    }
}
