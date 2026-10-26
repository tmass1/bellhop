import AppKit

/// Runs an action when the pointer rests on a status item's button for a moment, so passing over the menu bar
/// doesn't trigger it. Bellhop's icon opens its panel this way, and keepers open their app.
@MainActor
final class HoverOpener: NSResponder {
    static let dwell: TimeInterval = 0.25

    private weak var button: NSStatusBarButton?
    private let action: () -> Void
    private var pending: DispatchWorkItem?

    init(button: NSStatusBarButton, action: @escaping () -> Void) {
        self.button = button
        self.action = action
        super.init()
        button.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    required init?(coder: NSCoder) { nil }

    // There's no cancelling on exit: macOS 27 sends the button a spurious exit moments after the pointer arrives,
    // while it hasn't moved. When the pause ends, the pointer has to still be on the button instead.
    override func mouseEntered(with event: NSEvent) {
        pending?.cancel()
        let open = DispatchWorkItem { [weak self] in
            guard let self, NSEvent.pressedMouseButtons == 0,
                  button?.window?.frame.contains(NSEvent.mouseLocation) == true else { return }
            action()
        }
        pending = open
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: open)
    }

    /// A click got there first.
    func cancel() {
        pending?.cancel()
    }
}
