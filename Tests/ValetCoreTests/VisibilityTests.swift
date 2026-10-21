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
