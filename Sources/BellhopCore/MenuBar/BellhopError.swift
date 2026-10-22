import Foundation

public enum BellhopError: Error, Codable, Sendable, Equatable {
    case notTrusted
    case appNotRunning
    case iconNotFound(String)
    case ambiguous(String, [String])
    case itemNotFound(path: String, available: [String])
    case submenu(String)
    case disabled(String)
    case needsConfirmation(String)
    case panelApp(String)
    case noResponse(String)
    case pressFailed(String, code: Int32)
    case badRequest(String)

    public var message: String {
        switch self {
        case .notTrusted:
            "Bellhop needs Accessibility access. Open System Settings › Privacy & Security › Accessibility and turn on "
                + "Bellhop."
        case .appNotRunning:
            "Bellhop isn't running. Open Bellhop.app, then try again."
        case .iconNotFound(let name):
            "No menu bar icon matches \"\(name)\". Run `bellhop list` to see them."
        case .ambiguous(let name, let matches):
            "\"\(name)\" matches several icons: \(matches.joined(separator: ", ")). Use a fuller name."
        case .itemNotFound(let path, let available):
            available.isEmpty
                ? "No menu item at \"\(path)\"."
                : "No menu item at \"\(path)\". Items there: \(available.joined(separator: ", "))."
        case .submenu(let path):
            "\"\(path)\" is a submenu. Add the item inside it to the path."
        case .disabled(let path):
            "\"\(path)\" is disabled right now."
        case .needsConfirmation(let path):
            "\"\(path)\" can't be undone. Run it again with --confirm."
        case .panelApp(let name):
            "\(name) opens a panel, not a menu. Run \"\(name)\" on its own to open it."
        case .noResponse(let name):
            "\(name) didn't respond when Bellhop pressed it. Some apps only react to a real click."
        case .pressFailed(let path, let code):
            "Couldn't press \"\(path)\" (Accessibility error \(code))."
        case .badRequest(let detail):
            "Bad request: \(detail)"
        }
    }
}

extension BellhopError: LocalizedError {
    public var errorDescription: String? { message }
}
