import ArgumentParser
import Foundation
import ValetCore

/// The `valet` command. It talks to the running Valet app over a Unix socket, so only the app needs
/// Accessibility access.
@main
struct Valet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "valet",
        abstract: "Search and run menu bar items from the command line.",
        version: ValetCore.version,
        subcommands: [List.self, Menu.self, Run.self, Status.self]
    )
}

// MARK: Commands

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List every menu bar icon, left to right.")

    @Flag(help: "Print the full scan as JSON.")
    var json = false

    @Flag(help: "Print every runnable menu path Valet can see without opening menus.")
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

    @Argument(help: "The icon's name, as `valet list` shows it.")
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
            print("  Opens a panel, not a menu. `valet run \"\(icon.name)\"` opens it.")
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
        abstract: "Press a menu item, e.g. valet run \"Mark › Settings…\". A bare icon name presses the icon."
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

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check that Valet is running and has access.")

    func run() throws {
        let response = try send(.status)
        guard let status = response.status else { throw ExitCode.failure }
        print("Valet \(status.version) is running (pid \(status.pid)).")
        print(status.trusted ? "Accessibility: on" : "Accessibility: off. \(ValetError.notTrusted.message)")
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
    } catch let error as ValetError {
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
    }
}
