import Foundation

/// Turns one JSON request line into one JSON response line. The app runs this behind its socket.
public struct RequestHandler: Sendable {
    private let engine: MenuBarEngine
    private let capture: @Sendable () async -> SystemSnapshot
    private let status: @Sendable () -> StatusInfo
    private let history: HistoryStore
    private let showPalette: @Sendable (String?) async -> Void
    private let keep: @Sendable (MenuBarIcon, Bool) async -> [String]

    public init(
        engine: MenuBarEngine,
        capture: @escaping @Sendable () async -> SystemSnapshot,
        status: @escaping @Sendable () -> StatusInfo,
        history: HistoryStore = HistoryStore(),
        showPalette: @escaping @Sendable (String?) async -> Void = { _ in },
        keep: @escaping @Sendable (MenuBarIcon, Bool) async -> [String] = { _, _ in [] }
    ) {
        self.engine = engine
        self.capture = capture
        self.status = status
        self.history = history
        self.showPalette = showPalette
        self.keep = keep
    }

    public func handle(_ data: Data) async -> Data {
        let response: Response
        do {
            let request = try IPC.decoder().decode(Request.self, from: data)
            response = try await respond(to: request)
        } catch let error as BellhopError {
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
        case .search(let query):
            let index = SearchIndex(icons: try await engine.snapshot(capture()).icons)
            let saved = history.load()
            let hits = index.search(query, boosts: saved.boosts()).map { result in
                SearchHit(
                    path: result.candidate.path, kind: result.candidate.kind.rawValue,
                    enabled: result.candidate.entry?.enabled ?? true, shortcut: result.candidate.entry?.shortcut,
                    pinned: saved.isPinned(result.candidate.key)
                )
            }
            return Response(hits: hits)
        case .palette(let query):
            await showPalette(query)
            return Response()
        case .keep(let name, let shouldKeep):
            let icons = try await engine.snapshot(capture()).icons
            let icon = try MenuPaths.resolveIcon(name, in: icons)
            // Answer with the names people see rather than icon IDs.
            let names = Dictionary(icons.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            return Response(keepers: await keep(icon, shouldKeep).map { names[$0] ?? $0 })
        }
    }
}
