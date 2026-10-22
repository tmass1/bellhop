import AppKit
import ValetCore

/// Keeps Valet's divider just left of Valet's icon. Tucked, it's wide enough that macOS collapses it and every
/// icon to its left behind the overflow arrow. Arranging, it's a thin line. See `DividerLayout` for the numbers.
@MainActor
final class DividerController {
    static let iconName = "Valet"
    static let dividerName = "ValetDivider"
    /// First-run spot for Valet's icon. macOS orders items by this number (larger is further left); on the M5 Max
    /// 250 landed just left of Apple's own items. New items otherwise start far left, which means tucked.
    static let firstRunPosition = 250.0

    private let icon: NSStatusItem
    private let engine: MenuBarEngine
    private var divider: NSStatusItem?
    private(set) var arranging = false
    private var attachedTo: Double?
    private var reattaching = false
    private var pendingFollow: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

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
        attach()
    }

    // MARK: Attaching

    private static func key(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    private var iconPosition: Double? {
        UserDefaults.standard.object(forKey: Self.key(Self.iconName)) as? Double
    }

    /// Re-creates the divider directly left of the icon. Valet never removes its own icon: removing a status item
    /// deletes its stored position.
    private func attach() {
        guard let window = icon.button?.window, window.frame.minX >= 1 else {
            // Not laid out yet; its frame is still at x 0.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.attach() }
            return
        }
        reattaching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.reattaching = false }
        if let divider { NSStatusBar.system.removeStatusItem(divider) }
        storeDividerPosition()
        attachedTo = iconPosition
        let divider = NSStatusBar.system.statusItem(withLength: DividerLayout.arrangingWidth)
        divider.autosaveName = Self.dividerName
        divider.button?.setAccessibilityLabel("Valet divider")
        self.divider = divider
        styleDivider()
        resize()
    }

    /// macOS reads this when the divider is created. On 27 it drops it again once the divider is collapsed
    /// (tucked), so it's written fresh before every creation rather than relied on afterwards.
    private func storeDividerPosition() {
        guard let position = iconPosition else { return }
        let key = Self.key(Self.dividerName)
        let wanted = DividerLayout.dividerPosition(forIcon: position)
        if (UserDefaults.standard.object(forKey: key) as? Double) != wanted {
            UserDefaults.standard.set(wanted, forKey: key)
        }
    }

    private func styleDivider() {
        guard let button = divider?.button else { return }
        button.image = arranging ? Self.lineImage : nil
        button.toolTip = arranging
            ? "Icons left of this line are tucked away. ⌘-drag Valet’s icon to move it."
            : nil
    }

    /// Sets the divider's width for the current mode and layout.
    private func resize() {
        guard let divider else { return }
        if arranging {
            divider.length = DividerLayout.arrangingWidth
            return
        }
        guard let window = icon.button?.window, let screen = window.screen else { return }
        let iconMinX = window.frame.minX
        let notchMaxX = screen.auxiliaryTopRightArea.map { Double($0.minX) }
        Task {
            var appMenusMaxX: Double?
            if notchMaxX == nil, let front = NSWorkspace.shared.frontmostApplication {
                appMenusMaxX = await engine.appMenusMaxX(pid: front.processIdentifier)
            }
            let boundary = DividerLayout.leftBoundary(
                screenMinX: screen.frame.minX, notchMaxX: notchMaxX, appMenusMaxX: appMenusMaxX
            )
            // If Valet's own icon has no room to its left, a wide divider can't help; leave it thin.
            let width = DividerLayout.tuckingWidth(iconMinX: iconMinX, leftBoundary: boundary)
            guard !arranging else { return }
            divider.length = width ?? DividerLayout.arrangingWidth
        }
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
