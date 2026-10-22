import Foundation
import Testing
@testable import BellhopCore

@Test func requestsRoundTripThroughJSON() throws {
    let requests: [Request] = [.status, .list, .menu(icon: "Mark"), .run(path: "Mark › Settings…", confirm: true)]
    for request in requests {
        let data = try IPC.encoder().encode(request)
        #expect(try IPC.decoder().decode(Request.self, from: data) == request)
    }
}

@Test func socketCarriesOneRequestAndOneResponse() throws {
    let path = NSTemporaryDirectory() + "bellhop-test-\(getpid()).sock"
    let server = SocketServer(path: path) { request in
        Data("echo:".utf8) + request
    }
    try server.start()
    defer { server.stop() }
    let reply = try SocketClient.send(Data("hello".utf8), path: path)
    #expect(String(decoding: reply, as: UTF8.self) == "echo:hello")
}

@Test func clientReportsWhenTheAppIsntRunning() {
    #expect(throws: BellhopError.appNotRunning) {
        try SocketClient.send(Data("hi".utf8), path: NSTemporaryDirectory() + "bellhop-missing.sock")
    }
}

@Test func handlerAnswersListAndReportsErrors() async throws {
    let system = try FixtureAccessibility("macos27-laptop-overflow")
    let env = system.file.system
    let handler = RequestHandler(
        engine: MenuBarEngine(system: system),
        capture: { env },
        status: { StatusInfo(version: "test", trusted: true, pid: 1) }
    )
    let list = try IPC.decoder().decode(
        Response.self, from: await handler.handle(try IPC.encoder().encode(Request.list))
    )
    #expect(list.snapshot?.icons.count == 22)

    let quit = try IPC.decoder().decode(
        Response.self,
        from: await handler.handle(try IPC.encoder().encode(Request.run(path: "Mark › Quit Mark", confirm: false)))
    )
    #expect(quit.error == .needsConfirmation("Mark › Quit Mark"))

    let garbage = try IPC.decoder().decode(Response.self, from: await handler.handle(Data("nope".utf8)))
    #expect(garbage.error == .badRequest("couldn't read the request"))
}
