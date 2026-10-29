//
//  LightningRPC.swift
//  FullyNoded-Server
//
//  JSON-RPC to lightningd over its unix socket (<lightning-dir>/<network>/lightning-rpc), the
//  way lightning-cli does it: no process to spawn and nothing to parse but JSON. Only this
//  macOS user can open the socket.
//

import Foundation
import Darwin

enum LightningRPCError: Error, Equatable {
    /// No socket, or nothing listening on it: lightningd isn't running (or is still starting).
    case notRunning
    /// lightningd answered with an error.
    case rpc(code: Int, message: String)
    case io(String)

    var message: String {
        switch self {
        case .notRunning: return "Core Lightning isn't running."
        case .rpc(_, let message): return message
        case .io(let message): return message
        }
    }
}

enum LightningRPC {
    private static let queue = DispatchQueue(label: "fns.lightning-rpc", qos: .userInitiated, attributes: .concurrent)

    /// Calls `method`; the completion runs on the main queue.
    static func call(socketPath: String, method: String, params: Any = [String: Any](),
                     timeout: TimeInterval = 15, completion: @escaping (Result<Any, LightningRPCError>) -> Void) {
        queue.async {
            let result = callSync(socketPath: socketPath, method: method, params: params, timeout: timeout)
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func callSync(socketPath: String, method: String, params: Any, timeout: TimeInterval) -> Result<Any, LightningRPCError> {
        guard FileManager.default.fileExists(atPath: socketPath) else { return .failure(.notRunning) }
        let request: [String: Any] = ["jsonrpc": "2.0", "id": "fns-\(UUID().uuidString)", "method": method, "params": params]
        guard let body = try? JSONSerialization.data(withJSONObject: request) else {
            return .failure(.io("Couldn't encode the \(method) request."))
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(.io("socket: \(String(cString: strerror(errno)))")) }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else { return .failure(.io("The lightning-rpc path is too long for a unix socket.")) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            return .failure(code == ECONNREFUSED || code == ENOENT ? .notRunning : .io("connect: \(String(cString: strerror(code)))"))
        }

        // Send it all.
        var sent = 0
        while sent < body.count {
            let n = body.withUnsafeBytes { write(fd, $0.baseAddress! + sent, body.count - sent) }
            guard n > 0 else { return .failure(.io("write: \(String(cString: strerror(errno)))")) }
            sent += n
        }

        // lightningd sends one JSON object per reply (big ones arrive in pieces): read until the
        // buffer parses.
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                if let reply = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] {
                    if let error = reply["error"] as? [String: Any] {
                        return .failure(.rpc(code: error["code"] as? Int ?? 0,
                                             message: error["message"] as? String ?? "Unknown Core Lightning error."))
                    }
                    return .success(reply["result"] ?? [:])
                }
            } else if n == 0 {
                return .failure(.io("Core Lightning closed the connection."))
            } else if errno == EAGAIN || errno == EINTR {
                continue
            } else {
                return .failure(.io("read: \(String(cString: strerror(errno)))"))
            }
        }
        return .failure(.io("Core Lightning didn't answer \(method) in time."))
    }
}
