import Testing
@testable import ValetCore

@Test func dividerSitsJustLeftOfValetsIcon() {
    #expect(DividerLayout.dividerPosition(forIcon: 250) == 250.5)
}

@Test func tuckingWidthIsJustPastTheRoomLeftOfTheIcon() {
    // Spike geometry: notch ends at x 957, the icon sits at 1330. 373 pt of room, so 413 pt tucks.
    #expect(DividerLayout.tuckingWidth(iconMinX: 1330, leftBoundary: 957) == 413)
    #expect(DividerLayout.tuckingWidth(iconMinX: 950, leftBoundary: 957) == nil)
    #expect(DividerLayout.tuckingWidth(iconMinX: 0, leftBoundary: 957) == nil)
}

@Test func roomStartsAtTheNotchOrTheAppMenus() {
    #expect(DividerLayout.leftBoundary(screenMinX: 0, notchMaxX: 957, appMenusMaxX: 396) == 957)
    #expect(DividerLayout.leftBoundary(screenMinX: 0, notchMaxX: nil, appMenusMaxX: 396) == 396)
    #expect(DividerLayout.leftBoundary(screenMinX: 2560, notchMaxX: nil, appMenusMaxX: 396) == 2560)
    #expect(DividerLayout.leftBoundary(screenMinX: 0, notchMaxX: nil, appMenusMaxX: nil) == 0)
}

@Test func sectionsPutTuckedIconsFirst() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let sections = MenuBarSections(try await MenuBarEngine(system: system).scan(system.file.system))
    #expect(sections.tucked.map(\.name) == ["Burn", "Dev Server Manager", "Creative Cloud", "Ollama", "ChatGPT",
                                            "Private Internet Access"])
    #expect(sections.inBar.count == 16)
    #expect(sections.inBar.first?.name == "Dropbox")
}
