// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// A holder that takes a connection and never answers it: a fetch from it is under way until it is
/// cancelled. It says once a fetch has connected, so a test can stop one that has begun.
final class SilentHolder: Sendable {
    let port: Int
    private let socket: Int32
    private let connected = Shared()

    init() throws {
        #if canImport(Darwin)
        let listening = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        #else
        let listening = Glibc.socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian  // 127.0.0.1
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                unsafe bind(listening, address, length) == 0 && getsockname(listening, address, &length) == 0
            }
        }
        guard bound, listen(listening, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
        socket = listening
        port = Int(UInt16(bigEndian: address.sin_port))
        let connected = self.connected
        Thread.detachNewThread {
            // Held open and never read from or written to.
            if accept(listening, nil, nil) >= 0 { connected.withLock { $0 = true } }
        }
    }

    var hasConnection: Bool { connected.withLock { $0 } }

    /// The flag, shared with the thread that accepts.
    private final class Shared: Sendable {
        private let flag = Mutex(false)
        func withLock<T>(_ body: (inout Bool) -> T) -> T { flag.withLock { body(&$0) } }
    }

    deinit { close(socket) }
}
