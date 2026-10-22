import Testing
@testable import ValetCore

@Test func keepersSitBetweenTheDividerAndValetInOrder() {
    let positions = KeeperLayout.positions(count: 3, iconPosition: 250)
    #expect(positions == [250.45, 250.25, 250.05])
    // Larger is further left: first keeper leftmost, all right of the divider and left of Valet.
    #expect(positions == positions.sorted(by: >))
    #expect(positions.allSatisfy { $0 < DividerLayout.dividerPosition(forIcon: 250) && $0 > 250 })
    #expect(KeeperLayout.positions(count: 1, iconPosition: 250) == [250.45])
    #expect(KeeperLayout.positions(count: 0, iconPosition: 250).isEmpty)
}

@Test func statusTextIsLiveValuesNotLabels() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let icons = try await MenuBarEngine(system: system).scan(system.file.system).icons
    let byName = Dictionary(icons.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    #expect(byName["Burn"]?.statusText == "52%")
    #expect(byName["Fritter"]?.statusText == "3")
    #expect(byName["Mark"]?.statusText == nil)
    #expect(byName["PasswordsMenuBarExtra"]?.statusText == nil)
}

@Test func keeperTitlesAreReReadFromTheLastScan() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let engine = MenuBarEngine(system: system)
    let icons = try await engine.scan(system.file.system).icons
    let burn = try #require(icons.first { $0.name == "Burn" })
    let titles = await engine.titles(of: [burn.id, "missing#0"])
    #expect(titles == [burn.id: "52%"])
}
