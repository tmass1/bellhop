import AppKit
import BellhopCore

/// Keepers: tucked icons you chose to keep, shown again as Bellhop's own status items, in your order, between the
/// divider and Bellhop's icon. The real icons stay tucked; Bellhop never moves them.
@MainActor
final class KeeperController: NSObject {
    private static let keptKey = "BellhopKeepers"
    private static let refreshInterval: TimeInterval = 30

    private let engine: MenuBarEngine
    private let mirror: MenuMirror
    /// Kept icon IDs (bundle ID + index), left to right.
    private(set) var kept: [String]
    private var items: [String: NSStatusItem] = [:]
    private var icons: [String: MenuBarIcon] = [:]
    private var timer: Timer?
    private var hovers: [String: HoverOpener] = [:]
    /// The keeper whose app was opened by resting on it, until the next click anywhere. Resting on it again
    /// meanwhile does nothing: pressing a panel app's icon again would close the panel you just opened.
    private var openedByHover: String?
    private var clickMonitor: Any?
    /// Called after keepers are added, removed or reordered, so the divider can resize.
    var onLayoutChange: (() -> Void)?

    init(engine: MenuBarEngine, mirror: MenuMirror) {
        self.engine = engine
        self.mirror = mirror
        kept = UserDefaults.standard.stringArray(forKey: Self.keptKey) ?? []
        super.init()
    }

    /// The leftmost keeper's left edge, if any are showing. The divider's room starts left of it.
    var leftmostMinX: CGFloat? {
        kept.compactMap { items[$0]?.button?.window?.frame.minX }.filter { $0 >= 1 }.min()
    }

    func isKept(_ id: String) -> Bool { kept.contains(id) }

    // MARK: Changing what's kept

    /// Called when the kept list changes, so the Bellhop panel can redraw its sections.
    var onKeptChange: (([String]) -> Void)?

    func setKept(_ ids: [String], iconPosition: Double?) {
        guard ids != kept else { return }
        kept = ids
        UserDefaults.standard.set(ids, forKey: Self.keptKey)
        rebuild(iconPosition: iconPosition)
        onKeptChange?(ids)
    }

    func toggle(_ id: String, iconPosition: Double?) {
        setKept(isKept(id) ? kept.filter { $0 != id } : kept + [id], iconPosition: iconPosition)
    }

    /// Takes the latest scan: new status, new menus, and icons that came or went.
    func update(with snapshot: MenuBarSnapshot, iconPosition: Double?) {
        icons = Dictionary(snapshot.icons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if Set(items.keys) != Set(kept.filter { icons[$0] != nil }) {
            rebuild(iconPosition: iconPosition)
        } else {
            kept.forEach(style)
        }
        startRefreshing()
    }

    // MARK: Items

    /// Re-creates every keeper at its slot. Removing a status item deletes its stored position, so each one is
    /// written fresh right before its item is created.
    private func rebuild(iconPosition: Double?) {
        // Take the old items out before letting them go. Releasing a status item makes AppKit clear its saved
        // position and post a notification right away; the divider reacts by reading `items`, which must not
        // be mid-assignment then (Swift aborts on that overlapping access).
        let old = Array(items.values)
        items = [:]
        hovers = [:]
        old.forEach { NSStatusBar.system.removeStatusItem($0) }
        let showing = kept.filter { icons[$0] != nil }
        let positions = KeeperLayout.positions(count: showing.count, iconPosition: iconPosition ?? 250)
        for (id, position) in zip(showing, positions) {
            let name = Self.autosaveName(for: id)
            UserDefaults.standard.set(position, forKey: "NSStatusItem Preferred Position \(name)")
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = name
            item.button?.target = self
            item.button?.action = #selector(keeperClicked(_:))
            item.button?.identifier = NSUserInterfaceItemIdentifier(id)
            if let button = item.button {
                hovers[id] = HoverOpener(button: button) { [weak self] in self?.hovered(id) }
            }
            items[id] = item
            style(id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.onLayoutChange?() }
    }

    private static func autosaveName(for id: String) -> String {
        ItemNames.keeper(id, generation: DividerController.generation)
    }

    /// The keepers' windows, for checking where macOS put them.
    var windows: [NSWindow] { kept.compactMap { items[$0]?.button?.window } }

    /// Bellhop's items were renamed: re-create the keepers under the new names.
    func renamed(iconPosition: Double?) {
        rebuild(iconPosition: iconPosition)
    }

    /// A keeper shows the app's icon (approved Oct 22, replacing status text: a bare "1" or "3" doesn't say
    /// which app it is). Status stays in the tooltip.
    private func style(_ id: String) {
        guard let button = items[id]?.button, let icon = icons[id] else { return }
        button.toolTip = icon.statusText.map { "\(icon.name) · \($0)" } ?? icon.name
        button.setAccessibilityLabel(icon.name)
        button.title = ""
        button.image = AppIcons.image(for: icon)
        button.imagePosition = .imageOnly
    }

    @objc private func keeperClicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue else { return }
        hovers[id]?.cancel()
        open(id, clicked: true)
    }

    /// Resting on a keeper opens its app, as a click does: menus show beside it, panels open under it.
    private func hovered(_ id: String) {
        guard openedByHover != id, items[id]?.menu == nil else { return }
        openedByHover = id
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                MainActor.assumeIsolated { self.clickedElsewhere() }
            }
        }
        open(id, clicked: false)
    }

    private func clickedElsewhere() {
        openedByHover = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// Only a click says so when the app ignores Bellhop's press: on hover, an alert would be out of nowhere.
    private func open(_ id: String, clicked: Bool) {
        guard let icon = icons[id], let button = items[id]?.button else { return }
        if mirror.menu(for: icon) != nil {
            showMirror(of: icon, id: id)
            return
        }
        // A panel, or a menu that only exists while open. The engine reads such a menu once (it then shows here),
        // or presses the real tucked icon and moves its panel under this keeper.
        guard let window = button.window, let screen = window.screen else { return }
        // Panels hang from the keeper's right edge and open to the left, toward the middle of the screen.
        let x = Double(window.frame.maxX)
        let screenMaxX = Double(screen.frame.maxX)
        Task {
            do {
                let opened = try await engine.open(
                    icon.name, alignTo: x, growsLeft: true, screenMaxX: screenMaxX, env: SystemSnapshot.capture()
                )
                icons[id] = opened
                if mirror.menu(for: opened) != nil {
                    showMirror(of: opened, id: id)
                } else if clicked, opened.menuAvailability == .noResponse {
                    MenuMirror.alert(BellhopError.noResponse(opened.name).message)
                }
            } catch let error as BellhopError {
                MenuMirror.alert(error.message)
            } catch {
                MenuMirror.alert(error.localizedDescription)
            }
        }
    }

    private func showMirror(of icon: MenuBarIcon, id: String) {
        guard let item = items[id], let menu = mirror.menu(for: icon) else { return }
        menu.delegate = self
        item.menu = menu
        item.button?.performClick(nil)
    }

    // MARK: Status

    private func startRefreshing() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
    }

    private func refreshStatus() {
        let ids = kept.filter { icons[$0] != nil }
        guard !ids.isEmpty else { return }
        Task {
            let titles = await engine.titles(of: ids)
            for id in ids {
                icons[id]?.title = titles[id]
                style(id)
            }
        }
    }
}

extension KeeperController: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        // Detach so the next click comes back through the keeper's action and gets a fresh mirror. A closed menu
        // can open on hover again.
        items.values.forEach { $0.menu = nil }
        openedByHover = nil
    }
}
