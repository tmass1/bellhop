import Testing
@testable import ValetCore

@Test func pathsSplitOnEitherSeparator() {
    #expect(MenuPaths.parse("Mark › Settings…") == ["Mark", "Settings…"])
    #expect(MenuPaths.parse("ChatGPT > Computer Use >  No Active Sessions ") == ["ChatGPT", "Computer Use",
                                                                                   "No Active Sessions"])
    #expect(MenuPaths.parse("  ") == [])
}

@Test func matchingIgnoresCaseSpacingEllipsisAndHyphenStyle() {
    #expect(MenuPaths.matches("settings", "Settings…"))
    #expect(MenuPaths.matches("Settings...", "Settings…"))
    #expect(MenuPaths.matches("wi-fi,  connected", "Wi‑Fi, connected"))
    #expect(!MenuPaths.matches("Setting", "Settings…"))
}

@Test func destructiveItemsNeedConfirmation() {
    for title in ["Quit ChatGPT", "Quit", "Delete All History", "Sign Out", "Reset Settings", "Restart to update"] {
        #expect(MenuPaths.isDestructive(title), "\(title)")
    }
    for title in ["Settings…", "Quiet Mode", "Resetting Soon", "Open at Login", "Capture Region"] {
        #expect(!MenuPaths.isDestructive(title), "\(title)")
    }
}

@Test func iconsResolveByNameLabelAppOrBundleID() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let icons = try await MenuBarEngine(system: system).scan(system.file.system).icons
    #expect(try MenuPaths.resolveIcon("battery", in: icons).app.bundleID == "com.apple.MenuBarAgent")
    #expect(try MenuPaths.resolveIcon("com.markapp.Mark", in: icons).name == "Mark")
    #expect(try MenuPaths.resolveIcon("Apple Passwords Key", in: icons).app.name == "PasswordsMenuBarExtra")
    #expect(throws: ValetError.iconNotFound("Nope")) { try MenuPaths.resolveIcon("Nope", in: icons) }
}

@Test func displayPathsListRunnableLeaves() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let icons = try await MenuBarEngine(system: system).scan(system.file.system).icons
    let paths = icons.flatMap(MenuPaths.displayPaths(for:))
    #expect(paths.contains("ChatGPT › Computer Use › No Active Sessions"))
    #expect(paths.contains("Mark › Settings…"))
    #expect(!paths.contains("ChatGPT › Computer Use"))
}
