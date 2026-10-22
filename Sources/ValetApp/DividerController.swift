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
    /// One divider on a notched screen; on a wide screen without a notch, several that together fill the room.
    private var dividers: [NSStatusItem] = []
    private(set) var arranging = false
    private var attachedTo: Double?
    private var reattaching = false
    private var pendingFollow: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    /// Left edge of Valet's leftmost visible item. Keepers sit between the divider and Valet's icon, so the room
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

    /// Re-creates the divider directly left of the icon. Valet never removes its own icon: removing a status item
    /// deletes its stored position.
    private func attach() {
        guard let window = icon.button?.window, window.frame.minX >= 1 else {
            // Not laid out yet; its frame is still at x 0.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.attach() }
            return
        }
        attachedTo = iconPosition
        // The icon may have moved: re-create every piece next to its new spot.
        dividers.forEach { NSStatusBar.system.removeStatusItem($0) }
        dividers = []
        apply([DividerLayout.arrangingWidth])
        resize()
    }

    /// Sets the pieces' widths, re-creating them when the count changes. Each one's position is written right
    /// before it's created: macOS reads it then, and on 27 drops it once the piece is collapsed.
    private func apply(_ widths: [Double]) {
        if widths.count != dividers.count {
            reattaching = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.reattaching = false }
            dividers.forEach { NSStatusBar.system.removeStatusItem($0) }
            dividers = widths.indices.map { index in
                let name = index == 0 ? Self.dividerName : "\(Self.dividerName) \(index + 1)"
                if let position = iconPosition {
                    let piece = DividerLayout.dividerPosition(forIcon: position) + 0.1 * Double(index)
                    UserDefaults.standard.set(piece, forKey: Self.key(name))
                }
                let divider = NSStatusBar.system.statusItem(withLength: widths[index])
                divider.autosaveName = name
                divider.button?.setAccessibilityLabel("Valet divider")
                return divider
            }
            styleDivider()
        }
        for (divider, width) in zip(dividers, widths) where divider.length != width {
            divider.length = width
        }
    }

    private func styleDivider() {
        guard let button = dividers.first?.button else { return }
        button.image = arranging ? Self.lineImage : nil
        button.toolTip = arranging
            ? "Icons left of this line are tucked away. ⌘-drag Valet’s icon to move it."
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
        Task {
            var appMenusMaxX: Double?
            if notchMaxX == nil {
                // Without a notch the app's own menus share the bar. If they can't be read, keep what's there
                // rather than guess: measuring from the screen's edge makes the dividers far too wide.
                guard let front = NSWorkspace.shared.frontmostApplication,
                      let maxX = await engine.appMenusMaxX(pid: front.processIdentifier) else { return }
                appMenusMaxX = maxX
            }
            let boundary = DividerLayout.leftBoundary(
                screenMinX: screen.frame.minX, notchMaxX: notchMaxX, appMenusMaxX: appMenusMaxX
            )
            let widths = DividerLayout.tuckingWidths(
                iconMinX: iconMinX, leftBoundary: boundary, notched: notchMaxX != nil,
                screenWidth: screen.frame.width
            )
            guard !arranging else { return }
            // If Valet's own items have no room to their left, wide dividers can't help; leave one thin one.
            apply(widths ?? [DividerLayout.arrangingWidth])
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
