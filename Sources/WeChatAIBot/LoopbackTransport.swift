import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The desktop and WSL panels share this bounded, IPv4-loopback-only transport.
/// HTTP parsing, authentication and actions stay in QQControlServer.
final class LoopbackListener {
    private let descriptor: Int32
    let port: UInt16
    private let slots = DispatchSemaphore(value: 32)
    init() throws {
        #if os(Linux)
        let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard descriptor >= 0 else { throw AppFailure.message("无法创建本机控制端口") }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(descriptor, 32) == 0 else {
            close(descriptor); throw AppFailure.message("本机控制端口绑定失败")
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard result == 0 else { close(descriptor); throw AppFailure.message("无法读取本机端口") }
        self.descriptor = descriptor; port = UInt16(bigEndian: address.sin_port)
    }
    func start(accepted: @escaping (LoopbackConnection) -> Void) {
        DispatchQueue(label: "dafeiyu.control.accept").async { [self] in
            while true {
                let socket = accept(descriptor, nil, nil)
                if socket < 0 { if errno == EINTR { continue }; return }
                guard slots.wait(timeout: .now()) == .success else { close(socket); continue }
                accepted(LoopbackConnection(descriptor: socket, release: { [slots] in slots.signal() }))
            }
        }
    }
    deinit { close(descriptor) }
}

final class LoopbackConnection {
    private let descriptor: Int32
    private let queue = DispatchQueue(label: "dafeiyu.control.client")
    private let lock = NSLock()
    private var cancelled = false
    private let release: () -> Void
    init(descriptor: Int32, release: @escaping () -> Void) {
        self.descriptor = descriptor; self.release = release
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        #if os(macOS)
        var yes: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }
    func read(_ completion: @escaping (Data?, Bool, Error?) -> Void) {
        queue.async { [self] in
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = recv(descriptor, &bytes, bytes.count, 0)
            if count > 0 { completion(Data(bytes.prefix(count)), false, nil) }
            else { completion(nil, true, count < 0 ? URLError(.networkConnectionLost) : nil) }
        }
    }
    func send(_ data: Data, completion: @escaping () -> Void) {
        queue.async { [self] in
            data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < data.count {
                    #if os(Linux)
                    let count = Glibc.send(descriptor, base.advanced(by: offset), data.count - offset, Int32(MSG_NOSIGNAL))
                    #else
                    let count = Darwin.send(descriptor, base.advanced(by: offset), data.count - offset, 0)
                    #endif
                    if count <= 0 { if count < 0 && errno == EINTR { continue }; break }
                    offset += count
                }
            }
            completion()
        }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return }; cancelled = true
        // Keep the descriptor allocated until in-flight IO has released this object.
        // This avoids closing a reused descriptor in a concurrent cancellation.
        shutdown(descriptor, Int32(SHUT_RDWR))
    }
    deinit { close(descriptor); release() }
}
