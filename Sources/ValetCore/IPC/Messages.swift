import Foundation

/// One request from the CLI (and later MCP) to the running app. Sent as one line of JSON.
public enum Request: Codable, Sendable, Equatable {
    case status
    case list
    case menu(icon: String)
    case run(path: String, confirm: Bool)
}

public struct StatusInfo: Codable, Sendable, Equatable {
    public var version: String
    public var trusted: Bool
    public var pid: Int32

    public init(version: String, trusted: Bool, pid: Int32) {
        self.version = version
        self.trusted = trusted
        self.pid = pid
    }
}

/// The app's answer: exactly one of the payloads, or an error.
public struct Response: Codable, Sendable {
    public var error: ValetError?
    public var status: StatusInfo?
    public var snapshot: MenuBarSnapshot?
    public var icon: MenuBarIcon?
    public var run: RunResult?

    public init(
        error: ValetError? = nil, status: StatusInfo? = nil, snapshot: MenuBarSnapshot? = nil,
        icon: MenuBarIcon? = nil, run: RunResult? = nil
    ) {
        self.error = error
        self.status = status
        self.snapshot = snapshot
        self.icon = icon
        self.run = run
    }
}

public enum IPC {
    /// `~/Library/Application Support/Valet/valet.sock`, readable only by this user.
    public static var socketPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Valet/valet.sock").path
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
