import CoreGraphics

/// One Accessibility element, behind a protocol so ValetCore can run against JSON fixtures in tests.
/// Elements aren't Sendable: create and use them only inside `MenuBarEngine`.
public protocol AXElement: AnyObject {
    func attribute(_ name: String) -> Result<AXAttributeValue, AXFailure>
    /// Reads several attributes in one round trip. Missing or failed attributes are left out.
    func attributes(_ names: [String]) -> [String: AXAttributeValue]
    func actionNames() -> [String]
    /// Returns nil on success.
    func perform(_ action: String) -> AXFailure?
}

/// Where elements come from: the live system, or fixtures in tests.
public protocol AccessibilitySystem: Sendable {
    var isTrusted: Bool { get }
    func application(pid: Int32) -> any AXElement
}

public enum AXAttributeValue {
    case string(String)
    case bool(Bool)
    case int(Int)
    case point(CGPoint)
    case size(CGSize)
    case elements([any AXElement])
    case element(any AXElement)
    case other

    var string: String? {
        if case .string(let value) = self, !value.isEmpty { return value }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var int: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var point: CGPoint? {
        if case .point(let value) = self { return value }
        return nil
    }

    var size: CGSize? {
        if case .size(let value) = self { return value }
        return nil
    }

    var elements: [any AXElement] {
        if case .elements(let value) = self { return value }
        return []
    }
}

/// An AXError code. Kept as a raw value so ValetCore's model doesn't depend on ApplicationServices.
public struct AXFailure: Error, Equatable, Sendable {
    public let code: Int32

    public init(code: Int32) {
        self.code = code
    }

    public static let failure = AXFailure(code: -25200)
    public static let cannotComplete = AXFailure(code: -25204)
    public static let attributeUnsupported = AXFailure(code: -25205)
    public static let actionUnsupported = AXFailure(code: -25206)
    public static let apiDisabled = AXFailure(code: -25211)
    public static let noValue = AXFailure(code: -25212)
}

/// Attribute, role and action names used by ValetCore.
enum AXName {
    static let title = "AXTitle"
    static let description = "AXDescription"
    static let help = "AXHelp"
    static let identifier = "AXIdentifier"
    static let role = "AXRole"
    static let subrole = "AXSubrole"
    static let position = "AXPosition"
    static let size = "AXSize"
    static let children = "AXChildren"
    static let enabled = "AXEnabled"
    static let markChar = "AXMenuItemMarkChar"
    static let cmdChar = "AXMenuItemCmdChar"
    static let cmdModifiers = "AXMenuItemCmdModifiers"
    static let extrasMenuBar = "AXExtrasMenuBar"
    static let menuBar = "AXMenuBar"

    static let menuRole = "AXMenu"
    static let groupRole = "AXGroup"
    static let buttonRole = "AXButton"

    static let press = "AXPress"
    static let cancel = "AXCancel"
}
