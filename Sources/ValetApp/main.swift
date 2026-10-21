import AppKit

// Placeholder shell so `make run` proves bundling and signing work. The real hanger menu and palette wait for the
// approved mocks (milestone 0) and land in milestones 3 and 4.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "hanger", accessibilityDescription: "Valet")
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
