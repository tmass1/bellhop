import AppKit

// Placeholder shell so `make run` proves bundling and signing work. The real hanger menu and palette wait for the
// approved mocks (milestone 0) and land in milestones 3 and 4.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Template image from Valet-Icon-Assets: AppKit tints it for light, dark and selected states. Always 18 pt.
        if let image = Bundle.main.image(forResource: "ValetMenuTemplate") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            item.button?.image = image
        }
        item.button?.toolTip = "Valet"
        item.button?.setAccessibilityLabel("Valet")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Valet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
