import ValetCore

/// The human-readable table printed after a run, for checking against the real menu bar.
enum Report {
    static func print(_ output: ProbeOutput, path: String) {
        let rows = output.apps
            .flatMap { app in app.items.map { (app, $0) } }
            .sorted { ($0.1.frame?.x ?? .infinity) < ($1.1.frame?.x ?? .infinity) }

        Swift.print("")
        Swift.print("macOS \(output.macOS.version) (\(output.macOS.build)) · \(output.hardware.model)")
        for screen in output.screens {
            let notch = screen.notch.map { " · notch x \(int($0.minX))–\(int($0.maxX))" } ?? ""
            Swift.print("Screen \(screen.index) \(screen.name): \(rect(screen.frame))\(notch)")
        }
        if let front = output.frontmostApp {
            let end = front.menusFrame.map { " · menus end at x \(int($0.maxX))" } ?? ""
            Swift.print("Frontmost: \(front.name)\(end)")
        }
        Swift.print("")

        let header = [pad("x", 7), pad("App", 24), pad("Item", 30), pad("Size", 9), pad("Hidden", 22), "Menu"]
        Swift.print(header.joined(separator: " "))
        Swift.print(String(repeating: "─", count: 112))
        for (app, item) in rows {
            let x = item.frame.map { int($0.x) } ?? "—"
            let size = item.frame.map { "\(int($0.width))×\(int($0.height))" } ?? "—"
            let hidden = item.hidden ? item.hiddenReasons.map(\.rawValue).joined(separator: ",") : ""
            let menu = item.menu.status == "readable" ? "\(item.menu.itemCount) items" : "not while closed"
            Swift.print([pad(x, 7), pad(app.name, 24), pad(item.label, 30), pad(size, 9), pad(hidden, 22), menu]
                .joined(separator: " "))
        }

        let summary = output.summary
        Swift.print("")
        Swift.print("\(summary.itemCount) items from \(summary.appsWithExtras) apps (\(summary.appsScanned) scanned) "
            + "in \(int(summary.totalMs)) ms. \(summary.hiddenCount) hidden.")
        if !summary.hiddenByReason.isEmpty {
            Swift.print("Hidden by reason: " + summary.hiddenByReason.sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        }
        if !summary.appsWithoutClosedMenu.isEmpty {
            Swift.print("No menu while closed: " + summary.appsWithoutClosedMenu.joined(separator: ", "))
        }
        if !summary.appsWithErrors.isEmpty {
            Swift.print("Errors: " + summary.appsWithErrors.joined(separator: ", "))
        }
        Swift.print("Slowest: " + summary.slowestApps.map { "\($0.name) \(int($0.ms)) ms" }.joined(separator: ", "))
        Swift.print("JSON: \(path)")
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count > width
            ? String(text.prefix(width - 1)) + "…"
            : text + String(repeating: " ", count: width - text.count)
    }

    private static func int(_ value: Double) -> String { String(Int(value.rounded())) }

    private static func rect(_ frame: Frame) -> String {
        "\(int(frame.width))×\(int(frame.height)) at (\(int(frame.x)), \(int(frame.y)))"
    }
}
