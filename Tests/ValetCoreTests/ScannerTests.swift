import Testing
@testable import ValetCore

@Test func laptopScanFindsEveryIconAndTheOverflowArrow() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let snapshot = try await MenuBarEngine(system: system).scan(system.file.system)

    #expect(snapshot.icons.count == 22)
    #expect(snapshot.overflowButton == Frame(x: 981.5, y: 1, width: 17.5, height: 30))
    #expect(snapshot.icons.map(\.frame!.x) == snapshot.icons.map(\.frame!.x).sorted())

    let collapsed = snapshot.icons.filter { $0.hiddenReasons.contains(.collapsedBehindOverflow) }.map(\.name)
    #expect(Set(collapsed) == ["Burn", "Dev Server Manager", "Creative Cloud", "Ollama", "ChatGPT",
                               "Private Internet Access"])
    #expect(snapshot.icons.filter { !$0.isHidden }.count == 16)
}

@Test func systemItemsAreNamedByLabelAndReadThroughTheirWrapper() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let icons = try await MenuBarEngine(system: system).scan(system.file.system).icons
    let agentNames = icons.filter { $0.app.bundleID == "com.apple.MenuBarAgent" }.map(\.name)
    #expect(agentNames == ["Battery", "Wi‑Fi, connected, 3 bars", "Custom Recording", "Control Center", "Clock"])
    #expect(icons.allSatisfy { $0.canPress })
}

@Test func labelsFallBackToTooltipThenAppName() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let icons = try await MenuBarEngine(system: system).scan(system.file.system).icons
    let byApp = Dictionary(icons.map { ($0.app.name, $0) }, uniquingKeysWith: { first, _ in first })
    #expect(byApp["Burn"]?.title == "52%")
    #expect(byApp["Dropbox"]?.label == "Dropbox 277.3.4925")
    #expect(byApp["Ollama"]?.label == "Ollama")
    #expect(byApp["Mark"]?.name == "Mark")
}

@Test func readableMenusAreMirroredAndOthersWaitForDemand() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let icons = try await MenuBarEngine(system: system).scan(system.file.system).icons
    #expect(icons.filter { $0.menuAvailability == .readable }.count == 6)
    let mark = try #require(icons.first { $0.name == "Mark" })
    #expect(mark.menu?.first == MenuEntry(title: "Capture Region", enabled: true, shortcut: "⌘4"))
    #expect(mark.menu?.contains { $0.mark == "✓" && $0.title == "Open at Login" } == true)
    #expect(icons.first { $0.name == "Dropbox" }?.menuAvailability == .onDemand)
}

@Test func externalDisplayHasNoOverflow() async throws {
    let system = try FixtureAccessibility("macos27-external-display")
    let snapshot = try await MenuBarEngine(system: system).scan(system.file.system)
    #expect(snapshot.overflowButton == nil)
    #expect(snapshot.icons.count == 23)
    #expect(snapshot.icons.allSatisfy { !$0.isHidden })
}

@Test func scanningWithoutAccessThrows() async throws {
    var system = try FixtureAccessibility("macos27-laptop-overflow")
    system.isTrusted = false
    await #expect(throws: ValetError.notTrusted) {
        try await MenuBarEngine(system: system).scan(system.file.system)
    }
}

@Test func processesWithoutIconsAreSkippedOnTheNextScan() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let engine = MenuBarEngine(system: system)
    let env = system.file.system
    _ = try await engine.scan(env)
    let firstScan = system.cache.lookups
    let second = try await engine.scan(env)
    let secondScan = system.cache.lookups - firstScan
    // Only apps with icons (18) are read again, plus the frontmost app's menus.
    #expect(secondScan < firstScan / 3)
    #expect(second.icons.count == 22)
    _ = try await engine.scan(env, full: true)
    #expect(system.cache.lookups - firstScan - secondScan == firstScan)
}
