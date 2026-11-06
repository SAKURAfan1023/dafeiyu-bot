#if os(Windows)
import Foundation
import WinSDK

/// Windows counterpart of the existing bounded loopback transport; HTTP policy stays in the control server.
final class LoopbackListener {
    private let descriptor: SOCKET
    let port: UInt16
    private let lock = NSLock()
    private var stopped = false
    private var started = false
    private let slots = DispatchSemaphore(value: 32)
    init() throws {
        var startup = WSADATA()
        guard WSAStartup(0x0202, &startup) == 0 else { throw AppFailure.message("无法初始化本机网络") }
        let descriptor = WinSDK.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP.rawValue)
        guard descriptor != INVALID_SOCKET else { WSACleanup(); throw AppFailure.message("无法创建本机控制端口") }
        var address = sockaddr_in()
        address.sin_family = ADDRESS_FAMILY(AF_INET)
        address.sin_addr.S_un.S_addr = UInt32(0x0100007f)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                WinSDK.bind(descriptor, $0, Int32(MemoryLayout<sockaddr_in>.size))
            }
        }
        var length = Int32(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard bound == 0, named == 0, WinSDK.listen(descriptor, 32) == 0 else {
            closesocket(descriptor); WSACleanup(); throw AppFailure.message("本机控制端口绑定失败")
        }
        var nonblocking: u_long = 1
        guard ioctlsocket(descriptor, FIONBIO, &nonblocking) == 0 else {
            closesocket(descriptor); WSACleanup(); throw AppFailure.message("无法配置本机控制端口")
        }
        self.descriptor = descriptor; port = UInt16(bigEndian: address.sin_port)
    }
    func start(accepted: @escaping (LoopbackConnection) -> Void) {
        lock.lock()
        guard !started, !stopped else { lock.unlock(); return }
        started = true; lock.unlock()
        DispatchQueue.global().async { [self] in
            while true {
                // Serialize nonblocking accept with close; a recycled SOCKET is never used by the accept loop.
                lock.lock()
                if stopped { lock.unlock(); return }
                let client = WinSDK.accept(descriptor, nil, nil)
                let code = client == INVALID_SOCKET ? WSAGetLastError() : 0
                lock.unlock()
                if client == INVALID_SOCKET {
                    guard code == WSAEWOULDBLOCK else { return }
                    Thread.sleep(forTimeInterval: 0.02); continue
                }
                var blocking: u_long = 0
                guard ioctlsocket(client, FIONBIO, &blocking) == 0 else { closesocket(client); continue }
                guard slots.wait(timeout: .now()) == .success else { closesocket(client); continue }
                accepted(LoopbackConnection(descriptor: client, release: { [slots] in slots.signal() }))
            }
        }
    }
    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }; stopped = true
        WinSDK.shutdown(descriptor, SD_BOTH); closesocket(descriptor)
    }
    deinit { stop(); WSACleanup() }
}

final class LoopbackConnection {
    private let descriptor: SOCKET
    private let queue = DispatchQueue(label: "dafeiyu.control.client")
    private let lock = NSLock()
    private var cancelled = false
    private let release: () -> Void
    init(descriptor: SOCKET, release: @escaping () -> Void) {
        self.descriptor = descriptor; self.release = release
        var timeout: DWORD = 15_000
        withUnsafePointer(to: &timeout) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<DWORD>.size) {
                _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, Int32(MemoryLayout<DWORD>.size))
                _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, Int32(MemoryLayout<DWORD>.size))
            }
        }
    }
    func read(_ completion: @escaping (Data?, Bool, Error?) -> Void) {
        queue.async { [self] in
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = bytes.withUnsafeMutableBytes { buffer in
                WinSDK.recv(descriptor, buffer.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(buffer.count), 0)
            }
            if count > 0 { completion(Data(bytes.prefix(Int(count))), false, nil) }
            else { completion(nil, true, count < 0 ? URLError(.networkConnectionLost) : nil) }
        }
    }
    func send(_ data: Data, completion: @escaping () -> Void) {
        queue.async { [self] in
            data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < data.count {
                    let count = WinSDK.send(descriptor, base.advanced(by: offset).assumingMemoryBound(to: CChar.self), Int32(data.count - offset), 0)
                    if count <= 0 { break }; offset += Int(count)
                }
            }
            completion()
        }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return }; cancelled = true
        // Shutdown wakes outstanding IO; keep the handle alive until its queued operations release self.
        WinSDK.shutdown(descriptor, SD_BOTH)
    }
    deinit { closesocket(descriptor); release() }
}
#endif
