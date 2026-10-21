import ArgumentParser
import ValetCore

/// The `valet` command. It will talk to the running app over a Unix socket (milestone 2); for now it only reports
/// its version.
@main
struct Valet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "valet",
        abstract: "Search and run menu bar items from the command line.",
        version: ValetCore.version
    )
}
