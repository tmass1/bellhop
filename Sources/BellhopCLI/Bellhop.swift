import ArgumentParser
import Foundation
import BellhopCore

/// The `bellhop` command. It talks to the running Bellhop app over a Unix socket, so only the app needs
/// Accessibility access.
@main
struct Bellhop: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bellhop",
        abstract: "Search and run menu bar items from the command line.",
        version: BellhopCore.version,
        subcommands: [List.self, Menu.self, Run.self, Search.self, Palette.self, Keep.self, Tuck.self, Status.self]
    )
}

// MARK: Commands

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List every menu bar icon, left to right.")

    @Flag(help: "Print the full scan as JSON.")
    var json = false

    @Flag(help: "Print every runnable menu path Bellhop can see without opening menus.")
    var paths = false

    func run() throws {
        let response = try send(.list)
        guard let snapshot = response.snapshot else { throw ExitCode.failure }
        if json { return printJSON(snapshot) }
        if paths {
            for icon in snapshot.icons { MenuPaths.displayPaths(for: icon).forEach { print($0) } }
            return
        }
        let rows = snapshot.icons.map { icon in
            [icon.name, visibility(icon), menuSummary(icon), icon.title.flatMap { $0 == icon.name ? nil : $0 } ?? ""]
        }
        printTable(header: ["Icon", "Where", "Menu", "Shows"], rows: rows)
        let hidden = snapshot.icons.filter(\.isHidden).count
        print("\n\(snapshot.icons.count) icons, \(hidden) hidden. Scanned in \(Int(snapshot.scanMs)) ms.")
    }
}

struct Menu: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show an icon's menu. Menus that only exist while open are opened briefly to read them."
    )

    @Argument(help: "The icon's name, as `bellhop list` shows it.")
    var icon: String

    @Flag(help: "Print the icon as JSON.")
    var json = false

    func run() throws {
        let response = try send(.menu(icon: icon))
        guard let icon = response.icon else { throw ExitCode.failure }
        if json { return printJSON(icon) }
        print(icon.name)
        switch icon.menuAvailability {
        case .panel:
            print("  Opens a panel, not a menu. `bellhop run \"\(icon.name)\"` opens it.")
        case .noResponse:
            print("  Didn't respond to Bellhop's press. Some apps only react to a real click.")
        case .readable, .onDemand:
            printTree(icon.menu ?? [], depth: 1)
        }
    }

    private func printTree(_ entries: [MenuEntry], depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        for entry in entries {
            if entry.isSeparator {
                print(indent + "────")
                continue
            }
            var line = indent + (entry.mark.map { "\($0) " } ?? "") + (entry.title ?? "(untitled)")
            if let shortcut = entry.shortcut { line += "    \(shortcut)" }
            if !entry.enabled { line += "    (disabled)" }
            print(line)
            if let children = entry.children { printTree(children, depth: depth + 1) }
        }
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Press a menu item, e.g. bellhop run \"Mark › Settings…\". A bare icon name presses the icon."
    )

    @Argument(help: "Icon name, then menu titles, separated by › or >.")
    var path: String

    @Flag(help: "Allow items that can't be undone (Quit, Delete, Sign Out, Reset…).")
    var confirm = false

    @Flag(help: "Print the result as JSON.")
    var json = false

    func run() throws {
        let response = try send(.run(path: path, confirm: confirm))
        guard let result = response.run else { throw ExitCode.failure }
        if json { return printJSON(result) }
        print("Pressed \(result.path)")
    }
}

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search icons and menu items the way the palette does, best match first."
    )

    @Argument(help: "What to look for, e.g. \"snooze hour\".")
    var query: String

    @Option(help: "How many results to show.")
    var limit = 10

    @Flag(help: "Print results as JSON.")
    var json = false

    func run() throws {
        let response = try send(.search(query: query))
        let hits = Array((response.hits ?? []).prefix(limit))
        if json { return printJSON(hits) }
        if hits.isEmpty {
            print("No matches. Menus Bellhop hasn't read yet aren't searched: try `bellhop menu <icon>`.")
        }
        for hit in hits {
            var line = hit.path
            if let shortcut = hit.shortcut { line += "    \(shortcut)" }
            if !hit.enabled { line += "    (disabled)" }
            if hit.pinned { line += "    (pinned)" }
            print(line)
        }
    }
}

struct Palette: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open the palette, optionally with a search typed in.")

    @Argument(help: "Optional search to start with.")
    var query: String?

    func run() throws {
        _ = try send(.palette(query: query))
    }
}

struct Keep: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Keep an icon in the menu bar: Bellhop shows it next to its own icon, even when it's tucked."
    )

    @Argument(help: "The icon's name, as `bellhop list` shows it.")
    var icon: String

    func run() throws {
        let response = try send(.keep(icon: icon, keep: true))
        print("In the menu bar: \((response.keepers ?? []).joined(separator: ", "))")
    }
}

struct Tuck: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Tuck a kept icon away again.")

    @Argument(help: "The icon's name, as `bellhop list` shows it.")
    var icon: String

    func run() throws {
        let response = try send(.keep(icon: icon, keep: false))
        let kept = response.keepers ?? []
        print(kept.isEmpty ? "No keepers." : "In the menu bar: \(kept.joined(separator: ", "))")
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check that Bellhop is running and has access.")

    func run() throws {
        let response = try send(.status)
        guard let status = response.status else { throw ExitCode.failure }
        print("Bellhop \(status.version) is running (pid \(status.pid)).")
        print(status.trusted ? "Accessibility: on" : "Accessibility: off. \(BellhopError.notTrusted.message)")
    }
}

// MARK: Helpers

/// Sends a request to the app and turns errors into a message and an exit code.
private func send(_ request: Request) throws -> Response {
    do {
        let data = try SocketClient.send(try IPC.encoder().encode(request))
        let response = try IPC.decoder().decode(Response.self, from: data)
        if let error = response.error { throw error }
        return response
    } catch let error as BellhopError {
        FileHandle.standardError.write(Data((error.message + "\n").utf8))
        switch error {
        case .needsConfirmation: throw ExitCode(2)
        case .appNotRunning: throw ExitCode(3)
        default: throw ExitCode.failure
        }
    }
}

private func printJSON(_ value: some Encodable) {
    let encoder = IPC.encoder()
    encoder.outputFormatting.insert(.prettyPrinted)
    if let data = try? encoder.encode(value) { print(String(decoding: data, as: UTF8.self)) }
}

private func printTable(header: [String], rows: [[String]]) {
    let widths = header.indices.map { column in
        min(36, ([header] + rows).map { $0[column].count }.max() ?? 0)
    }
    func line(_ cells: [String]) -> String {
        zip(cells, widths).map { cell, width in
            cell.count > width
                ? String(cell.prefix(width - 1)) + "…"
                : cell.padding(toLength: width, withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
    }
    print(line(header))
    rows.forEach { print(line($0)) }
}

private func visibility(_ icon: MenuBarIcon) -> String {
    if icon.hiddenReasons.contains(.collapsedBehindOverflow) { return "collapsed (behind »)" }
    if icon.hiddenReasons.contains(.underNotch) { return "under the notch" }
    if icon.hiddenReasons.contains(.behindAppMenus) { return "behind app menus" }
    if icon.isHidden { return "hidden" }
    return "visible"
}

private func menuSummary(_ icon: MenuBarIcon) -> String {
    switch icon.menuAvailability {
    case .readable: "\(MenuPaths.entries(for: icon).count) items"
    case .onDemand: "read on open"
    case .panel: "panel"
    case .noResponse: "no response"
    }
}
