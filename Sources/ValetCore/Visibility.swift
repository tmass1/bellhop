import CoreGraphics

/// A rectangle in Accessibility coordinates: origin at the top-left of the primary screen, y growing downward.
public struct Frame: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    /// Converts an AppKit rect (bottom-left origin, y up) to Accessibility coordinates.
    public init(cocoa rect: CGRect, primaryScreenHeight: Double) {
        self.init(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
}

/// One display, reduced to what visibility needs. All frames are in Accessibility coordinates.
public struct ScreenGeometry: Codable, Sendable, Equatable {
    public var index: Int
    public var name: String
    public var frame: Frame
    /// Height of the menu bar strip; 0 when the menu bar auto-hides.
    public var menuBarHeight: Double
    /// The camera housing between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. Nil on screens without one.
    public var notch: Frame?

    public init(index: Int, name: String, frame: Frame, menuBarHeight: Double, notch: Frame?) {
        self.index = index
        self.name = name
        self.frame = frame
        self.menuBarHeight = menuBarHeight
        self.notch = notch
    }
}

public enum HiddenReason: String, Codable, Sendable, CaseIterable {
    /// Width or height is 1 point or less.
    case zeroSize
    /// The item's center isn't on any screen.
    case offScreen
    /// The item overlaps the notch.
    case underNotch
    /// The item starts left of the end of the frontmost app's menus, on the same screen, so the menus cover it.
    case behindAppMenus
    /// macOS 27+: the item sits left of Apple's "Show Hidden Menu Bar Items" arrow, which collapses everything
    /// that doesn't fit. Collapsed items report frames piled up just left of the arrow.
    case collapsedBehindOverflow
}

public enum Visibility {
    /// The screen whose bounds contain the item's center, if any.
    public static func screen(containing item: Frame, in screens: [ScreenGeometry]) -> ScreenGeometry? {
        screens.first { $0.frame.cgRect.contains(item.center) }
    }

    /// Every reason an item is hidden; empty means it's visible.
    /// - Parameters:
    ///   - appMenus: the union of the frontmost app's menu bar item frames, if known.
    ///   - overflowButton: the frame of macOS 27's overflow arrow, when it's showing. Don't pass it for the arrow itself.
    public static func hiddenReasons(
        for item: Frame, screens: [ScreenGeometry], appMenus: Frame?, overflowButton: Frame? = nil
    ) -> [HiddenReason] {
        var reasons: [HiddenReason] = []
        if item.width <= 1 || item.height <= 1 {
            reasons.append(.zeroSize)
        }
        guard let screen = screen(containing: item, in: screens) else {
            reasons.append(.offScreen)
            return reasons
        }
        // CGRect.intersects counts touching edges; a non-empty intersection means real overlap.
        // swiftlint:disable:next is_disjoint
        if let notch = screen.notch, !item.cgRect.intersection(notch.cgRect).isEmpty {
            reasons.append(.underNotch)
        }
        if let appMenus, Visibility.screen(containing: appMenus, in: screens)?.index == screen.index,
           item.minX < appMenus.maxX {
            reasons.append(.behindAppMenus)
        }
        if let overflowButton, Visibility.screen(containing: overflowButton, in: screens)?.index == screen.index,
           item.minX < overflowButton.minX {
            reasons.append(.collapsedBehindOverflow)
        }
        return reasons
    }
}
