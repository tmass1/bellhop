import CoreGraphics
import Testing
@testable import BellhopCore

@Test func dividerSitsJustLeftOfBellhopsIcon() {
    #expect(DividerLayout.dividerPosition(forIcon: 250) == 250.5)
}

@Test func itemNamesKeepTodaysNamesUntilARename() {
    #expect(ItemNames.icon(generation: 0) == "Bellhop")
    #expect(ItemNames.divider(index: 0, generation: 0) == "BellhopDivider")
    #expect(ItemNames.divider(index: 1, generation: 0) == "BellhopDivider 2")
    #expect(ItemNames.keeper("com.tommymassaro.burn#0", generation: 0) == "BellhopKeeper com.tommymassaro.burn 0")
    #expect(ItemNames.icon(generation: 1) == "Bellhop g1")
    #expect(ItemNames.divider(index: 1, generation: 1) == "BellhopDivider g1 2")
    #expect(ItemNames.keeper("com.fiplab.clipboard#0", generation: 1) == "BellhopKeeper g1 com.fiplab.clipboard 0")
}

@Test func tuckingWidthIsJustPastTheRoomLeftOfTheIcon() {
    // Spike geometry: notch ends at x 957, the icon sits at 1330. 373 pt of room, so 413 pt tucks.
    #expect(DividerLayout.tuckingWidth(iconMinX: 1330, leftBoundary: 957) == 413)
    #expect(DividerLayout.tuckingWidth(iconMinX: 950, leftBoundary: 957) == nil)
    #expect(DividerLayout.tuckingWidth(iconMinX: 0, leftBoundary: 957) == nil)
}

@Test func roomStartsAtTheNotchOrTheAppMenus() {
    #expect(DividerLayout.leftBoundary(screenMinX: 0, notchMaxX: 957, appMenusWidth: 396) == 957)
    #expect(DividerLayout.leftBoundary(screenMinX: 0, notchMaxX: nil, appMenusWidth: 396) == 396)
    #expect(DividerLayout.leftBoundary(screenMinX: 2560, notchMaxX: nil, appMenusWidth: 396) == 2956)
    #expect(DividerLayout.leftBoundary(screenMinX: 0, notchMaxX: nil, appMenusWidth: nil) == 0)
}

@Test func appMenusOnTheOtherDisplayCountFromThatDisplaysEdge() {
    // Oct 27: Cinema Display at 0–2560, MacBook screen at 2560–4288. Chrome, active on the MacBook, has menus
    // reaching 3183, which is 623 pt into that screen; the Cinema Display's bar shows them to 623 too.
    let screens = [0.0...2560, 2560.0...4288]
    #expect(DividerLayout.appMenusWidth(menusMinX: 2570, menusMaxX: 3183, screens: screens) == 623)
    #expect(DividerLayout.appMenusWidth(menusMinX: 10, menusMaxX: 396, screens: screens) == 396)
    #expect(DividerLayout.appMenusWidth(menusMinX: -900, menusMaxX: -500, screens: screens) == nil)
}

@Test func appMenusArentMeasuredBeforeTheyreLaidOut() {
    let log = ActionLog()
    func bar(_ widths: [Double]) -> FakeElement {
        var x = 10.0
        let menus = widths.map { width in
            defer { x += max(width, 1) }
            return FakeElement([
                AXName.position: .point(CGPoint(x: width > 0 ? x : 0, y: 0)),
                AXName.size: .size(CGSize(width: width, height: 24)),
            ], log: log)
        }
        let menuBar = FakeElement([AXName.children: .elements(menus)], log: log)
        return FakeElement([AXName.menuBar: .element(menuBar)], log: log)
    }
    // Figma right as it comes to the front: only the Apple menu has a width.
    #expect(AXReader().appMenusFrame(bar([34] + Array(repeating: 0, count: 12))) == nil)
    #expect(AXReader().appMenusFrame(bar([34, 66, 42]))?.maxX == 152)
    #expect(AXReader().appMenusFrame(bar([0, 0, 0])) == nil)
}

@Test func sectionsPutTuckedIconsFirst() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let sections = MenuBarSections(try await MenuBarEngine(system: system).scan(system.file.system))
    #expect(sections.tucked.map(\.name) == ["Burn", "Dev Server Manager", "Creative Cloud", "Ollama", "ChatGPT",
                                            "Private Internet Access"])
    #expect(sections.inBar.count == 16)
    #expect(sections.inBar.first?.name == "Dropbox")
}

@Test func notchedScreensUseOneOverWideDivider() {
    #expect(DividerLayout.tuckingWidths(iconMinX: 1330, leftBoundary: 957, notched: true, screenWidth: 1728) == [413])
}

@Test func screensWithoutANotchSplitTheRoomIntoPiecesThatFit() {
    // Cinema Display, Oct 22: room 1,800 pt (app menus end at 372, ◆ at 2172); 2 × 880 tucked every icon.
    #expect(DividerLayout.tuckingWidths(iconMinX: 2172, leftBoundary: 372, notched: false, screenWidth: 2560)
        == [880, 880])
    // Small room: one piece.
    #expect(DividerLayout.tuckingWidths(iconMinX: 900, leftBoundary: 400, notched: false, screenWidth: 1920)
        == [460])
    #expect(DividerLayout.tuckingWidths(iconMinX: 420, leftBoundary: 400, notched: false, screenWidth: 1920) == nil)
}
