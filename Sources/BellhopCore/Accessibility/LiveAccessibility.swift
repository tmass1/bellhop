import ApplicationServices

/// The real Accessibility API.
public struct LiveAccessibility: AccessibilitySystem {
    /// Per-app messaging timeout. Short, so one hung app can't stall a scan.
    public var timeout: Float

    public init(timeout: Float = 0.5) {
        self.timeout = timeout
    }

    public var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and adds Bellhop to the Accessibility list, switched off.
    public static func requestAccess() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func application(pid: Int32) -> any AXElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return LiveElement(element)
    }
}

final class LiveElement: AXElement {
    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    func attribute(_ name: String) -> Result<AXAttributeValue, AXFailure> {
        var raw: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, name as CFString, &raw)
        guard err == .success, let raw else {
            return .failure(AXFailure(code: err == .success ? AXError.noValue.rawValue : err.rawValue))
        }
        return .success(Self.decode(raw))
    }

    func attributes(_ names: [String]) -> [String: AXAttributeValue] {
        var raw: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(
            element, names as CFArray, AXCopyMultipleAttributeOptions(), &raw
        )
        guard err == .success, let values = raw as? [CFTypeRef] else { return [:] }
        var result: [String: AXAttributeValue] = [:]
        for (name, value) in zip(names, values) {
            let decoded = Self.decode(value)
            if case .other = decoded { continue }
            result[name] = decoded
        }
        return result
    }

    func actionNames() -> [String] {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(element, &raw) == .success else { return [] }
        return (raw as? [String]) ?? []
    }

    func setPosition(_ point: CGPoint) -> AXFailure? {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        let err = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        return err == .success ? nil : AXFailure(code: err.rawValue)
    }

    func perform(_ action: String) -> AXFailure? {
        let err = AXUIElementPerformAction(element, action as CFString)
        return err == .success ? nil : AXFailure(code: err.rawValue)
    }

    // swiftlint:disable force_cast
    private static func decode(_ value: CFTypeRef) -> AXAttributeValue {
        let typeID = CFGetTypeID(value)
        switch typeID {
        case CFStringGetTypeID():
            return .string(value as! String)
        case CFBooleanGetTypeID():
            return .bool(CFBooleanGetValue((value as! CFBoolean)))
        case CFNumberGetTypeID():
            return .int((value as! NSNumber).intValue)
        case AXUIElementGetTypeID():
            return .element(LiveElement(value as! AXUIElement))
        case CFArrayGetTypeID():
            let items = (value as? [CFTypeRef]) ?? []
            return .elements(items.compactMap { item in
                CFGetTypeID(item) == AXUIElementGetTypeID() ? LiveElement(item as! AXUIElement) : nil
            })
        case AXValueGetTypeID():
            let axValue = value as! AXValue
            switch AXValueGetType(axValue) {
            case .cgPoint:
                var point = CGPoint.zero
                return AXValueGetValue(axValue, .cgPoint, &point) ? .point(point) : .other
            case .cgSize:
                var size = CGSize.zero
                return AXValueGetValue(axValue, .cgSize, &size) ? .size(size) : .other
            default:
                return .other
            }
        default:
            return .other
        }
    }
    // swiftlint:enable force_cast
}
