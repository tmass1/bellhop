import CoreGraphics
import Testing
@testable import ValetCore

// Geometry from a real setup: a 2560×1440 external display as primary, with a notched 1728×1117 built-in to its right.
private let primaryHeight = 1440.0
private let external = ScreenGeometry(
    index: 0, name: "External", frame: Frame(x: 0, y: 0, width: 2560, height: 1440), menuBarHeight: 30, notch: nil
)
private let builtIn = ScreenGeometry(
    index: 1,
    name: "Built-in",
    frame: Frame(cocoa: CGRect(x: 2560, y: 323, width: 1728, height: 1117), primaryScreenHeight: primaryHeight),
    menuBarHeight: 32,
    notch: Frame(x: 3331.5, y: 0, width: 185, height: 32)
)
private let screens = [external, builtIn]

@Test func cocoaFramesFlipToAccessibilityCoordinates() {
    #expect(builtIn.frame == Frame(x: 2560, y: 0, width: 1728, height: 1117))
    let lower = Frame(cocoa: CGRect(x: 0, y: 0, width: 100, height: 40), primaryScreenHeight: primaryHeight)
    #expect(lower.y == 1400)
}

@Test func visibleItemHasNoReasons() {
    let item = Frame(x: 4000, y: 0, width: 30, height: 32)
    #expect(Visibility.hiddenReasons(for: item, screens: screens, appMenus: nil).isEmpty)
}

@Test func itemOverlappingNotchIsHidden() {
    let item = Frame(x: 3320, y: 0, width: 30, height: 32)
    #expect(Visibility.hiddenReasons(for: item, screens: screens, appMenus: nil) == [.underNotch])
}

@Test func itemTouchingNotchEdgeIsVisible() {
    let item = Frame(x: 3516.5, y: 0, width: 30, height: 32)
    #expect(Visibility.hiddenReasons(for: item, screens: screens, appMenus: nil).isEmpty)
}

@Test func itemLeftOfAppMenusEndIsHidden() {
    let appMenus = Frame(x: 2570, y: 0, width: 900, height: 32)
    let item = Frame(x: 3400, y: 0, width: 30, height: 32)
    #expect(Visibility.hiddenReasons(for: item, screens: screens, appMenus: appMenus) == [.underNotch, .behindAppMenus])
}

@Test func appMenusOnAnotherScreenDontHideItems() {
    let appMenus = Frame(x: 0, y: 0, width: 900, height: 30)
    let item = Frame(x: 4000, y: 0, width: 30, height: 32)
    #expect(Visibility.hiddenReasons(for: item, screens: screens, appMenus: appMenus).isEmpty)
    let leftOfMenusElsewhere = Frame(x: 2600, y: 0, width: 30, height: 32)
    #expect(Visibility.hiddenReasons(for: leftOfMenusElsewhere, screens: screens, appMenus: appMenus).isEmpty)
}

@Test func zeroSizeItemIsHidden() {
    let item = Frame(x: 4000, y: 0, width: 0, height: 0)
    #expect(Visibility.hiddenReasons(for: item, screens: screens, appMenus: nil) == [.zeroSize])
}

@Test func offScreenItemIsHidden() {
    let item = Frame(x: -500, y: 0, width: 30, height: 30)
    #expect(Visibility.hiddenReasons(for: item, screens: screens, appMenus: nil) == [.offScreen])
    let zeroAndOff = Frame(x: 9000, y: -50, width: 0, height: 0)
    #expect(Visibility.hiddenReasons(for: zeroAndOff, screens: screens, appMenus: nil) == [.zeroSize, .offScreen])
}

@Test func screenWithoutNotchNeverReportsUnderNotch() {
    let item = Frame(x: 1200, y: 0, width: 30, height: 30)
    #expect(Visibility.hiddenReasons(for: item, screens: screens, appMenus: nil).isEmpty)
}

// Captured on macOS 27 with the built-in display as the only screen: six icons collapsed behind the arrow at 981.5.
private let laptopOnly = [
    ScreenGeometry(
        index: 0, name: "Built-in", frame: Frame(x: 0, y: 0, width: 1728, height: 1117), menuBarHeight: 33,
        notch: Frame(x: 771.5, y: 0, width: 185, height: 32)
    ),
]
private let overflowArrow = Frame(x: 981.5, y: 1, width: 17.5, height: 30)

@Test func itemsLeftOfOverflowArrowAreCollapsed() {
    let devServer = Frame(x: 958, y: 4.5, width: 41, height: 24)
    #expect(Visibility.hiddenReasons(
        for: devServer, screens: laptopOnly, appMenus: nil, overflowButton: overflowArrow
    ) == [.collapsedBehindOverflow])
    let burn = Frame(x: 926, y: 4.5, width: 73, height: 24)
    #expect(Visibility.hiddenReasons(
        for: burn, screens: laptopOnly, appMenus: nil, overflowButton: overflowArrow
    ) == [.underNotch, .collapsedBehindOverflow])
}

@Test func itemsRightOfOverflowArrowAreVisible() {
    let dropbox = Frame(x: 1005, y: 4.5, width: 38, height: 24)
    #expect(Visibility.hiddenReasons(
        for: dropbox, screens: laptopOnly, appMenus: nil, overflowButton: overflowArrow
    ).isEmpty)
}

@Test func overflowArrowOnAnotherScreenDoesntCollapseItems() {
    let item = Frame(x: 900, y: 0, width: 30, height: 30)
    #expect(Visibility.hiddenReasons(
        for: item, screens: screens, appMenus: nil, overflowButton: Frame(x: 4000, y: 0, width: 18, height: 30)
    ).isEmpty)
}

// Cinema Display, Oct 22: dividers at 380–1194 and 1216–2030, arrow at 1184. Collapsed icons kept reporting their
// old spots, some right of the arrow.
@Test func iconsUnderValetsDividersAreTuckedWhateverTheyReport() {
    let cinema = [ScreenGeometry(
        index: 0, name: "Cinema", frame: Frame(x: 0, y: 0, width: 2560, height: 1440), menuBarHeight: 30, notch: nil
    )]
    let dividers = [Frame(x: 380, y: 2, width: 814, height: 24), Frame(x: 1216, y: 2, width: 814, height: 24)]
    let arrow = Frame(x: 1184, y: 1, width: 17.5, height: 27)
    let stale = Frame(x: 1516, y: 2, width: 24, height: 24)
    #expect(Visibility.hiddenReasons(
        for: stale, screens: cinema, appMenus: nil, overflowButton: arrow, dividers: dividers
    ) == [.collapsedBehindOverflow])
    let keeperSide = Frame(x: 2211, y: 2, width: 26, height: 24)
    #expect(Visibility.hiddenReasons(
        for: keeperSide, screens: cinema, appMenus: nil, overflowButton: arrow, dividers: dividers
    ).isEmpty)
}
