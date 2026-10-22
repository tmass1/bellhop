import Darwin
import Foundation

/// A minimal newline-delimited Unix socket server and client. One request line in, one response line out.
enum UnixSocket {
    struct Failure: Error, CustomStringConvertible {
        let call: String
        let code: Int32
        var description: String { "\(call) failed: \(String(cString: strerror(code)))" }
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw Failure(call: "socket path too long", code: ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return addr
    }

    static func setTimeout(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Reads until a newline or EOF, up to `limit` bytes.
    static func readLine(_ fd: Int32, limit: Int = 8 << 20) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < limit {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
            if buffer[count - 1] == UInt8(ascii: "\n") { break }
        }
        if data.last == UInt8(ascii: "\n") { data.removeLast() }
        return data
    }

    static func writeAll(_ fd: Int32, _ data: Data) {
        var payload = data
        payload.append(UInt8(ascii: "\n"))
        payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }
}

/// Listens on a Unix socket owned by this user. Each connection carries one request.
public final class SocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) async -> Data

    private let path: String
    private let handler: Handler
    private let lock = NSLock()
    private var listener: Int32 = -1

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocket.Failure(call: "socket", code: errno) }
        var addr = try UnixSocket.address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw UnixSocket.Failure(call: "bind", code: code)
        }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            throw UnixSocket.Failure(call: "listen", code: code)
        }
        lock.withLock { listener = fd }
        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "Valet socket"
        thread.start()
    }

    public func stop() {
        let fd = lock.withLock {
            defer { listener = -1 }
            return listener
        }
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            // Only this user's processes may talk to Valet.
            var uid = uid_t()
            var gid = gid_t()
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                close(client)
                continue
            }
            UnixSocket.setTimeout(client, seconds: 5)
            let request = UnixSocket.readLine(client)
            let handler = self.handler
            Task {
                let response = await handler(request)
                UnixSocket.writeAll(client, response)
                close(client)
            }
        }
    }
}

public enum SocketClient {
    /// Sends one request line and waits for the response. Throws `ValetError.appNotRunning` if nothing is listening.
    public static func send(_ request: Data, path: String = IPC.socketPath, timeout: Int = 30) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocket.Failure(call: "socket", code: errno) }
        defer { close(fd) }
        var addr = try UnixSocket.address(path)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw ValetError.appNotRunning }
        UnixSocket.setTimeout(fd, seconds: timeout)
        UnixSocket.writeAll(fd, request)
        return UnixSocket.readLine(fd)
    }
}
