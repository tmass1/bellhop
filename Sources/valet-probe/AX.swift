import ApplicationServices
import Foundation

/// Thin typed reads over the C Accessibility API. Only `Prober` calls these, so every AX call stays inside its actor.
enum AX {
    /// Reads several attributes in one round trip. Missing or failed attributes are left out of the result.
    static func values(_ el: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
        var raw: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(el, names as CFArray, AXCopyMultipleAttributeOptions(), &raw)
        guard err == .success, let array = raw as? [CFTypeRef] else { return [:] }
        var result: [String: CFTypeRef] = [:]
        for (name, value) in zip(names, array) where !isError(value) {
            result[name] = value
        }
        return result
    }

    struct Failure: Error {
        let code: AXError
    }

    static func value(_ el: AXUIElement, _ name: String) -> Result<CFTypeRef, Failure> {
        var raw: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, name as CFString, &raw)
        guard err == .success, let raw else { return .failure(Failure(code: err == .success ? .noValue : err)) }
        return .success(raw)
    }

    static func attributeNames(_ el: AXUIElement) -> [String] {
        var raw: CFArray?
        guard AXUIElementCopyAttributeNames(el, &raw) == .success else { return [] }
        return (raw as? [String]) ?? []
    }

    static func actionNames(_ el: AXUIElement) -> [String] {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(el, &raw) == .success else { return [] }
        return (raw as? [String]) ?? []
    }

    // MARK: Decoding values

    static func string(_ value: CFTypeRef?) -> String? {
        guard let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        let string = value as! String // swiftlint:disable:this force_cast
        return string.isEmpty ? nil : string
    }

    static func bool(_ value: CFTypeRef?) -> Bool? {
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean)) // swiftlint:disable:this force_cast
    }

    static func int(_ value: CFTypeRef?) -> Int? {
        guard let value, CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        return (value as? NSNumber)?.intValue
    }

    static func point(_ value: CFTypeRef?) -> CGPoint? {
        guard let axValue = axValue(value, .cgPoint) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: CFTypeRef?) -> CGSize? {
        guard let axValue = axValue(value, .cgSize) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    static func elements(_ value: CFTypeRef?) -> [AXUIElement] {
        guard let value, CFGetTypeID(value) == CFArrayGetTypeID(), let array = value as? [CFTypeRef] else {
            return []
        }
        return array.compactMap { item in
            // swiftlint:disable:next force_cast
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    /// A short, readable rendering of any attribute value, for discovering attributes we don't know yet.
    static func describe(_ value: CFTypeRef) -> String {
        let typeID = CFGetTypeID(value)
        let text: String
        if typeID == CFStringGetTypeID() {
            text = "\"\(value as! String)\"" // swiftlint:disable:this force_cast
        } else if typeID == CFBooleanGetTypeID() {
            text = bool(value) == true ? "true" : "false"
        } else if typeID == CFNumberGetTypeID() {
            text = "\(value as? NSNumber ?? 0)"
        } else if typeID == AXUIElementGetTypeID() {
            text = "<element \(role(of: value as! AXUIElement) ?? "?")>" // swiftlint:disable:this force_cast
        } else if typeID == CFArrayGetTypeID() {
            let array = value as? [CFTypeRef] ?? []
            text = "[\(array.prefix(5).map(describe).joined(separator: ", "))\(array.count > 5 ? ", …" : "")]"
        } else if typeID == AXValueGetTypeID() {
            text = describeAXValue(value as! AXValue) // swiftlint:disable:this force_cast
        } else {
            text = String(describing: value)
        }
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }

    // MARK: Private

    private static func isError(_ value: CFTypeRef) -> Bool {
        axValue(value, .axError) != nil
    }

    private static func axValue(_ value: CFTypeRef?, _ type: AXValueType) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue // swiftlint:disable:this force_cast
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    private static func role(of el: AXUIElement) -> String? {
        if case .success(let value) = self.value(el, kAXRoleAttribute) { return string(value) }
        return nil
    }

    private static func describeAXValue(_ value: AXValue) -> String {
        switch AXValueGetType(value) {
        case .cgPoint:
            var point = CGPoint.zero
            AXValueGetValue(value, .cgPoint, &point)
            return "point(\(point.x), \(point.y))"
        case .cgSize:
            var size = CGSize.zero
            AXValueGetValue(value, .cgSize, &size)
            return "size(\(size.width), \(size.height))"
        case .cgRect:
            var rect = CGRect.zero
            AXValueGetValue(value, .cgRect, &rect)
            return "rect(\(rect.origin.x), \(rect.origin.y), \(rect.width), \(rect.height))"
        case .cfRange:
            var range = CFRange()
            AXValueGetValue(value, .cfRange, &range)
            return "range(\(range.location), \(range.length))"
        case .axError:
            var err = AXError.success
            AXValueGetValue(value, .axError, &err)
            return "error(\(err.rawValue))"
        default:
            return "axvalue"
        }
    }
}
