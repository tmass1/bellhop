import AppKit

/// A borderless, non-activating panel: it takes keyboard input without pulling focus from the app you're in.
/// The Valet panel uses the menu material; the palette uses Liquid Glass where the system has it (macOS 26+).
final class FloatingPanel: NSPanel {
    /// Called when the panel stops being the key window, e.g. you click into another app.
    var onResignKey: (() -> Void)?

    init(content: NSView, cornerRadius: CGFloat = 10, glass: Bool = false) {
        super.init(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = Self.background(for: content, cornerRadius: cornerRadius, glass: glass)
    }

    private static func background(for content: NSView, cornerRadius: CGFloat, glass: Bool) -> NSView {
        if glass, #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.cornerRadius = cornerRadius
            view.contentView = content
            return view
        }
        let material = NSVisualEffectView()
        material.material = glass ? .popover : .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        return material
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
