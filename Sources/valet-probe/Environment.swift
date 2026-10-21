import AppKit
import Darwin
import ValetCore

/// Everything the probe needs from AppKit, captured once on the main thread and handed to `Prober` as plain values.
struct Snapshot: Sendable {
    var apps: [AppInfo]
    var frontmost: AppInfo?
    var screens: [ScreenGeometry]

    @MainActor
    static func capture(allProcesses: Bool) -> Snapshot {
        let workspace = NSWorkspace.shared
        var apps = workspace.runningApplications
            .filter { $0.processIdentifier > 0 }
            .map(AppInfo.init)
        if allProcesses {
            let known = Set(apps.map(\.pid))
            apps += userProcesses().filter { !known.contains($0.pid) && $0.pid != getpid() }
        }
        return Snapshot(
            apps: apps,
            frontmost: workspace.frontmostApplication.map(AppInfo.init),
            screens: screens()
        )
    }

    @MainActor
    private static func screens() -> [ScreenGeometry] {
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

    /// Processes owned by this user, for `--all-processes`. Catches helpers that own icons but aren't in NSWorkspace.
    private static func userProcesses() -> [AppInfo] {
        let capacity = Int(proc_listpids(UInt32(PROC_UID_ONLY), UInt32(getuid()), nil, 0)) / MemoryLayout<pid_t>.size
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity + 32)
        let bytes = proc_listpids(
            UInt32(PROC_UID_ONLY), UInt32(getuid()), &pids, Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).filter { $0 > 0 }.map { pid in
            var name = [CChar](repeating: 0, count: 256)
            proc_name(pid, &name, UInt32(name.count))
            let decoded = String(utf8String: name) ?? ""
            return AppInfo(
                name: decoded.isEmpty ? "pid \(pid)" : decoded, bundleID: nil, pid: pid, activationPolicy: "process"
            )
        }
    }
}

extension AppInfo {
    init(_ app: NSRunningApplication) {
        let policy = switch app.activationPolicy {
        case .regular: "regular"
        case .accessory: "accessory"
        case .prohibited: "prohibited"
        @unknown default: "unknown"
        }
        self.init(
            name: app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)",
            bundleID: app.bundleIdentifier,
            pid: app.processIdentifier,
            activationPolicy: policy
        )
    }
}

enum System {
    static var osInfo: OSInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return OSInfo(
            version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            build: sysctlString("kern.osversion") ?? "unknown"
        )
    }

    static var hardware: Hardware {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return Hardware(model: sysctlString("hw.model") ?? "unknown", arch: arch)
    }

    /// The app bundle macOS charges Accessibility to: the nearest ancestor whose executable lives in a `.app`.
    /// That's usually the terminal, but launchers can hand responsibility to a helper bundle (Claude Code's
    /// `claude.app` sits under Application Support, not /Applications), so report the path, not a display name.
    static func accessibilityHost() -> String? {
        var pid = getppid()
        while pid > 1 {
            if let path = executablePath(of: pid), let range = path.range(of: ".app/Contents/MacOS/") {
                return String(path[..<range.lowerBound]) + ".app"
            }
            guard let parent = parentPID(of: pid) else { break }
            pid = parent
        }
        return nil
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(utf8String: buffer)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(utf8String: buffer)
    }
}
