import AppKit
import BellhopCore

/// Keeps Bellhop's divider just left of Bellhop's icon. Tucked, it's wide enough that macOS collapses it and every
/// icon to its left behind the overflow arrow. Arranging, it's a thin line. See `DividerLayout` for the numbers.
@MainActor
final class DividerController {
    /// Bumped when macOS misplaces Bellhop's items; see `ItemNames` and `checkOrder()`.
    static var generation: Int {
        get { UserDefaults.standard.integer(forKey: "BellhopItemGeneration") }
        set { UserDefaults.standard.set(newValue, forKey: "BellhopItemGeneration") }
    }
    static var iconName: String { ItemNames.icon(generation: generation) }
    /// First-run spot for Bellhop's icon. macOS orders items by this number (larger is further left); on the M5 Max
    /// 250 landed just left of Apple's own items. New items otherwise start far left, which means tucked.
    static let firstRunPosition = 250.0

    private let icon: NSStatusItem
    private let engine: MenuBarEngine
    /// One divider on a notched screen; on a wide screen without a notch, several that together fill the room.
    private var dividers: [NSStatusItem] = []
    private(set) var arranging = false
    private var attachedTo: Double?
    private var reattaching = false
    private var pendingFollow: DispatchWorkItem?
    /// A re-measure after an app came to the front before its menus were laid out.
    private var pendingMeasure: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var renames = 0
    /// Keepers' windows, for checking that macOS put them left of the icon.
    var keeperWindows: (() -> [NSWindow])?
    /// Called after Bellhop's items were renamed, so keepers re-create theirs under the new names.
    var onRename: (() -> Void)?
    /// Left edge of Bellhop's leftmost visible item. Keepers sit between the divider and Bellhop's icon, so the room
    /// is measured from the leftmost of them.
    var leftmostItemMinX: (() -> CGFloat?)?

    init(icon: NSStatusItem, engine: MenuBarEngine) {
        self.icon = icon
        self.engine = engine
    }

    static func placeIconOnFirstRun() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key(iconName)) == nil {
            defaults.set(firstRunPosition, forKey: key(iconName))
        }
    }

    func start() {
        // A ⌘-drag records the icon's new position in our defaults and moves its window.
        observe(NotificationCenter.default, UserDefaults.didChangeNotification) { $0.iconMayHaveMoved() }
        if let window = icon.button?.window {
            observe(NotificationCenter.default, NSWindow.didMoveNotification, object: window) { $0.iconMayHaveMoved() }
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.resize() }
        // Without a notch, the frontmost app's menus share the bar, so the room changes with the app.
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { $0.resize() }
        attach()
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
        _ handler: @escaping @MainActor (DividerController) -> Void
    ) {
        observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        })
    }

    func toggleArranging() {
        arranging.toggle()
        apply([DividerLayout.arrangingWidth])
        styleDivider()
        resize()
    }

    // MARK: Attaching

    private static func key(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    /// The dividers' frames on screen while they're tucking, for telling which icons they hide.
    var tuckingFrames: [CGRect] {
        arranging ? [] : dividers.compactMap { $0.button?.window?.frame }.filter { $0.width > 40 }
    }

    var iconPosition: Double? {
        UserDefaults.standard.object(forKey: Self.key(Self.iconName)) as? Double
    }

    /// Re-creates the divider directly left of the icon. Bellhop never removes its own icon: removing a status item
    /// deletes its stored position.
    private func attach() {
        guard let window = icon.button?.window, window.frame.minX >= 1 else {
            // Not laid out yet; its frame is still at x 0.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.attach() }
            return
        }
        attachedTo = iconPosition
        // The icon may have moved: re-create every piece next to its new spot.
        removeDividers()
        apply([DividerLayout.arrangingWidth])
        resize()
    }

    /// Sets the pieces' widths, re-creating them when the count changes. Each one's position is written right
    /// before it's created: macOS reads it then, and on 27 drops it once the piece is collapsed.
    private func apply(_ widths: [Double]) {
        if widths.count != dividers.count {
            reattaching = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.reattaching = false }
            removeDividers()
            let created = widths.indices.map { index in
                let name = ItemNames.divider(index: index, generation: Self.generation)
                if let position = iconPosition {
                    let piece = DividerLayout.dividerPosition(forIcon: position) + 0.1 * Double(index)
                    UserDefaults.standard.set(piece, forKey: Self.key(name))
                }
                let divider = NSStatusBar.system.statusItem(withLength: widths[index])
                divider.autosaveName = name
                divider.button?.setAccessibilityLabel("Bellhop divider")
                return divider
            }
            dividers = created
            styleDivider()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.checkOrder() }
        }
        for (divider, width) in zip(dividers, widths) where divider.length != width {
            divider.length = width
        }
    }

    /// Empties `dividers` before the old items go away: releasing one posts notifications that call back into
    /// `resize()`, which reads `dividers`.
    private func removeDividers() {
        let old = dividers
        dividers = []
        old.forEach { NSStatusBar.system.removeStatusItem($0) }
    }

    /// Bellhop's divider and keepers belong left of its icon. If macOS put one right of it, the menu bar agent is
    /// placing the icon from a stale record of its own (see `ItemNames`), so every item is renamed. Twice at most
    /// per launch, so this can't loop.
    private func checkOrder() {
        guard renames < 2, let iconWindow = icon.button?.window, iconWindow.frame.minX >= 1 else { return }
        let ours = dividers.compactMap { $0.button?.window } + (keeperWindows?() ?? [])
        // Collapsed items sit near x 0, and items shown on the other display's bar can't be compared.
        let misplaced = ours.contains {
            $0.frame.minX >= 1 && $0.screen == iconWindow.screen && $0.frame.minX > iconWindow.frame.minX
        }
        guard misplaced else { return }
        renames += 1
        let oldKey = Self.key(Self.iconName)
        let position = iconPosition ?? Self.firstRunPosition
        Self.generation += 1
        UserDefaults.standard.set(position, forKey: Self.key(Self.iconName))
        UserDefaults.standard.removeObject(forKey: oldKey)
        icon.autosaveName = Self.iconName
        attachedTo = position
        onRename?()
        removeDividers()
        apply([DividerLayout.arrangingWidth])
        resize()
    }

    private func styleDivider() {
        guard let button = dividers.first?.button else { return }
        button.image = arranging ? Self.lineImage : nil
        button.toolTip = arranging
            ? "Icons left of this line are tucked away. ⌘-drag Bellhop’s icon to move it."
            : nil
    }

    /// Sets the dividers for the current mode and layout.
    func resize() {
        guard !dividers.isEmpty else { return }
        if arranging {
            apply([DividerLayout.arrangingWidth])
            styleDivider()
            return
        }
        guard let window = icon.button?.window, let screen = window.screen else { return }
        let iconMinX = min(window.frame.minX, leftmostItemMinX?() ?? window.frame.minX)
        let notchMaxX = screen.auxiliaryTopRightArea.map { Double($0.minX) }
        let screens = NSScreen.screens.map { Double($0.frame.minX)...Double($0.frame.maxX) }
        Task {
            var appMenusWidth: Double?
            if notchMaxX == nil {
                // Without a notch the app's own menus share the bar. If they can't be read, keep what's there
                // rather than guess: dividers that don't fit make macOS re-lay the bar out over and over (the «
                // arrow flickers). An app that just came to the front may not have laid its menus out yet, so
                // look again shortly.
                guard let front = NSWorkspace.shared.frontmostApplication,
                      let menus = await engine.appMenusFrame(pid: front.processIdentifier),
                      let width = DividerLayout.appMenusWidth(
                          menusMinX: menus.x, menusMaxX: menus.maxX, screens: screens
                      ) else { return measureAgain() }
                appMenusWidth = width
            }
            let boundary = DividerLayout.leftBoundary(
                screenMinX: screen.frame.minX, notchMaxX: notchMaxX, appMenusWidth: appMenusWidth
            )
            let widths = DividerLayout.tuckingWidths(
                iconMinX: iconMinX, leftBoundary: boundary, notched: notchMaxX != nil,
                screenWidth: screen.frame.width
            )
            guard !arranging else { return }
            // If Bellhop's own items have no room to their left, wide dividers can't help; leave one thin one.
            apply(widths ?? [DividerLayout.arrangingWidth])
        }
    }

    private func measureAgain() {
        guard pendingMeasure == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingMeasure = nil
            self?.resize()
        }
        pendingMeasure = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Following

    private func iconMayHaveMoved() {
        guard !reattaching else { return }
        if let position = iconPosition, abs(position - (attachedTo ?? .infinity)) > 0.05 {
            // Let the drag settle, then re-attach next to the icon's new spot.
            pendingFollow?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.attach() }
            pendingFollow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        } else {
            // Same position, new x: icons to its right changed, so the room did too.
            resize()
        }
    }

    private static let lineImage: NSImage = {
        let image = NSImage(size: NSSize(width: 2, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
