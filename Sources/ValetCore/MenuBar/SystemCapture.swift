import AppKit

extension SystemSnapshot {
    /// The app sets this so every capture knows where Valet's own dividers are (Cocoa screen coordinates).
    @MainActor public static var dividerFrames: () -> [CGRect] = { [] }

    /// Reads running apps, the frontmost app and the screens. AppKit wants this on the main thread.
    @MainActor
    public static func capture() -> SystemSnapshot {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
            .filter { $0.processIdentifier > 0 && $0.processIdentifier != getpid() }
            .map(RunningApp.init)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return SystemSnapshot(
            apps: apps,
            frontmost: workspace.frontmostApplication.map(RunningApp.init),
            screens: captureScreens(),
            dividers: dividerFrames().map { Frame(cocoa: $0, primaryScreenHeight: primaryHeight) }
        )
    }

    @MainActor
    private static func captureScreens() -> [ScreenGeometry] {
        let all = NSScreen.screens
        guard let primaryHeight = all.first?.frame.height else { return [] }
        return all.enumerated().map { index, screen in
            var notch: Frame?
            // Both areas are in global AppKit coordinates; the notch is the gap between them.
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let height = max(left.height, right.height)
                let gap = CGRect(
                    x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height
                )
                notch = Frame(cocoa: gap, primaryScreenHeight: primaryHeight)
            }
            return ScreenGeometry(
                index: index,
                name: screen.localizedName,
                frame: Frame(cocoa: screen.frame, primaryScreenHeight: primaryHeight),
                menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                notch: notch
            )
        }
    }
}

extension RunningApp {
    init(_ app: NSRunningApplication) {
        self.init(
            name: app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)",
            bundleID: app.bundleIdentifier,
            pid: app.processIdentifier
        )
    }
}
