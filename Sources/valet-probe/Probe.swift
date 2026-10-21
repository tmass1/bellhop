import AppKit
import ArgumentParser
import ValetCore

/// Milestone 1 spike: dumps every menu bar extra, its frame, whether it's hidden, and its menu tree as JSON.
/// Read-only. It never presses or opens anything.
@main
struct Probe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "valet-probe",
        abstract: "Dump every menu bar extra and its menu over Accessibility, as JSON."
    )

    @Option(help: "Folder for the JSON output.")
    var output = "probe-output"

    @Option(help: "How many submenu levels to walk.")
    var maxDepth = 6

    @Option(help: "Probe only the app with this bundle ID or name.")
    var app: String?

    @Flag(help: "Also probe every process you own that isn't a regular app, to catch helpers that own icons.")
    var allProcesses = false

    @Option(help: "Seconds to wait before reading, so you can bring another app to the front.")
    var delay: Double = 0

    @Option(help: "Accessibility messaging timeout per app, in seconds.")
    var timeout: Double = 0.5

    @Flag(help: "Open System Settings › Accessibility if access isn't granted.")
    var openSettings = false

    @Flag(help: "Skip the table; only write JSON.")
    var quiet = false

    mutating func run() async throws {
        let host = await MainActor.run { System.accessibilityHost() }
        guard checkAccess(host: host) else { throw ExitCode(2) }

        if delay > 0 {
            print("Reading in \(delay.formatted()) s. Switch to the app you want in front.")
            try await Task.sleep(for: .seconds(delay))
        }

        let clock = ContinuousClock()
        let start = clock.now
        let snapshot = await MainActor.run { [allProcesses] in Snapshot.capture(allProcesses: allProcesses) }
        let prober = Prober(maxDepth: maxDepth, timeout: timeout)

        var frontmost: FrontmostApp?
        if let front = snapshot.frontmost { frontmost = await prober.frontmostMenus(of: front) }
        var apps = snapshot.apps
        if let filter = app?.lowercased() {
            apps = apps.filter { $0.bundleID?.lowercased() == filter || $0.name.lowercased() == filter }
        }
        var results: [AppResult] = []
        for info in apps {
            results.append(await prober.probe(info, screens: snapshot.screens, appMenus: frontmost?.menusFrame))
        }

        let result = ProbeOutput(
            capturedAt: Date.now.ISO8601Format(),
            macOS: System.osInfo,
            hardware: System.hardware,
            accessibilityHost: host,
            screens: snapshot.screens,
            frontmostApp: frontmost,
            options: Options(maxDepth: maxDepth, allProcesses: allProcesses, app: app, delay: delay, timeout: timeout),
            summary: Self.summarize(results, totalMs: (clock.now - start).milliseconds),
            apps: results
        )
        let path = try write(result)
        if !quiet { Report.print(result, path: path) }
    }

    // MARK: Access

    private func checkAccess(host: String?) -> Bool {
        // Passing the prompt option adds the host app to the Accessibility list, switched off, so it's easy to find.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return true }
        let name = host ?? "your terminal app"
        print("""
        valet-probe needs Accessibility access, which macOS grants to \(name), the app it runs inside.

          1. Open System Settings › Privacy & Security › Accessibility.
          2. Turn on \(name). If it isn't listed, click + and add it.
          3. Run make probe again.
        """)
        if openSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    // MARK: Output

    private func write(_ result: ProbeOutput) throws -> String {
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(result)

        let stamp = result.capturedAt.replacingOccurrences(of: ":", with: "").prefix(17)
        let model = result.hardware.model.replacingOccurrences(of: ",", with: "-")
        let file = folder.appendingPathComponent("macOS\(result.macOS.version)-\(model)-\(stamp).json")
        try data.write(to: file)
        try data.write(to: folder.appendingPathComponent("latest.json"))
        return file.path
    }

    private static func summarize(_ apps: [AppResult], totalMs: Double) -> Summary {
        let items = apps.flatMap(\.items)
        var hiddenByReason: [String: Int] = [:]
        var menuStatusCounts: [String: Int] = [:]
        for item in items {
            for reason in item.hiddenReasons where item.hidden { hiddenByReason[reason.rawValue, default: 0] += 1 }
            menuStatusCounts[item.menu.status, default: 0] += 1
        }
        let withExtras = apps.filter { !$0.items.isEmpty }
        return Summary(
            appsScanned: apps.count,
            appsWithExtras: withExtras.count,
            itemCount: items.count,
            hiddenCount: items.filter(\.hidden).count,
            hiddenByReason: hiddenByReason,
            menuStatusCounts: menuStatusCounts,
            appsWithoutClosedMenu: withExtras
                .filter { $0.items.contains { $0.menu.status != "readable" } }
                .map(\.name),
            appsWithErrors: apps
                .filter { $0.extrasStatus != "ok" && $0.extrasStatus != "none" }
                .map { "\($0.name) (\($0.extrasStatus))" },
            totalMs: totalMs,
            slowestApps: apps.sorted { $0.ms > $1.ms }.prefix(5).map { Timing(name: $0.name, ms: $0.ms) }
        )
    }
}
