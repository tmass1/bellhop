import AppKit
import ValetCore

/// Keepers: tucked icons you chose to keep, shown again as Valet's own status items, in your order, between the
/// divider and Valet's icon. The real icons stay tucked; Valet never moves them.
@MainActor
final class KeeperController: NSObject {
    private static let keptKey = "ValetKeepers"
    private static let refreshInterval: TimeInterval = 30

    private let engine: MenuBarEngine
    private let mirror: MenuMirror
    /// Kept icon IDs (bundle ID + index), left to right.
    private(set) var kept: [String]
    private var items: [String: NSStatusItem] = [:]
    private var icons: [String: MenuBarIcon] = [:]
    private var timer: Timer?
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

    /// Called when the kept list changes, so the Valet panel can redraw its sections.
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
        items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
        items = [:]
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
            items[id] = item
            style(id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.onLayoutChange?() }
    }

    private static func autosaveName(for id: String) -> String {
        "ValetKeeper " + id.replacingOccurrences(of: "#", with: " ")
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
        guard let id = sender.identifier?.rawValue, let icon = icons[id] else { return }
        if mirror.menu(for: icon) != nil {
            showMirror(of: icon, id: id)
            return
        }
        // A panel, or a menu that only exists while open. The engine reads such a menu once (it then shows here),
        // or presses the real tucked icon and moves its panel under this keeper.
        guard let window = sender.window, let screen = window.screen else { return }
        let x = Double(window.frame.minX)
        let screenMaxX = Double(screen.frame.maxX)
        Task {
            do {
                let opened = try await engine.open(
                    icon.name, alignTo: x, screenMaxX: screenMaxX, env: SystemSnapshot.capture()
                )
                icons[id] = opened
                if mirror.menu(for: opened) != nil { showMirror(of: opened, id: id) }
            } catch let error as ValetError {
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
        // Detach so the next click comes back through the keeper's action and gets a fresh mirror.
        items.values.forEach { $0.menu = nil }
    }
}
