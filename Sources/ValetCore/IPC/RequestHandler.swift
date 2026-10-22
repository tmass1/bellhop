import Foundation

/// Turns one JSON request line into one JSON response line. The app runs this behind its socket.
public struct RequestHandler: Sendable {
    private let engine: MenuBarEngine
    private let capture: @Sendable () async -> SystemSnapshot
    private let status: @Sendable () -> StatusInfo

    public init(
        engine: MenuBarEngine,
        capture: @escaping @Sendable () async -> SystemSnapshot,
        status: @escaping @Sendable () -> StatusInfo
    ) {
        self.engine = engine
        self.capture = capture
        self.status = status
    }

    public func handle(_ data: Data) async -> Data {
        let response: Response
        do {
            let request = try IPC.decoder().decode(Request.self, from: data)
            response = try await respond(to: request)
        } catch let error as ValetError {
            response = Response(error: error)
        } catch is DecodingError {
            response = Response(error: .badRequest("couldn't read the request"))
        } catch {
            response = Response(error: .badRequest(error.localizedDescription))
        }
        return (try? IPC.encoder().encode(response)) ?? Data(#"{"error":{"badRequest":{"_0":"encoding"}}}"#.utf8)
    }

    private func respond(to request: Request) async throws -> Response {
        switch request {
        case .status:
            return Response(status: status())
        case .list:
            return Response(snapshot: try await engine.scan(capture()))
        case .menu(let icon):
            return Response(icon: try await engine.loadMenu(icon, env: capture()))
        case .run(let path, let confirm):
            return Response(run: try await engine.run(path, confirm: confirm, env: capture()))
        }
    }
}
