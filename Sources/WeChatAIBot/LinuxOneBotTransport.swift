#if os(Linux)
import Foundation
import NIOCore
import NIOPosix
import WebSocketKit

/// Owns one connection, its bounded inbound stream and its event-loop lifetime.
/// Ubuntu's system libcurl may omit WebSockets; HTTP model calls remain on URLSession.
@MainActor final class LinuxOneBotTransport {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var socket: WebSocket?
    private var waiter: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private(set) var closed = false
    let messages: AsyncThrowingStream<Data, Error>
    private let incoming: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        let stream = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        messages = stream.stream; incoming = stream.continuation
    }

    func connect(url: URL, token: String) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !closed else { continuation.resume(throwing: CancellationError()); return }
                waiter = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                    self?.close(error: URLError(.timedOut))
                }
                var configuration = WebSocketClient.Configuration(maxFrameSize: 1_048_576)
                configuration.maxAccumulatedFrameSize = 1_048_576
                configuration.maxAccumulatedFrameCount = 32
                let incoming = incoming
                WebSocket.connect(scheme: url.scheme ?? "ws", host: url.host ?? "127.0.0.1",
                    port: url.port ?? 80, path: url.path.isEmpty ? "/" : url.path, query: url.query,
                    headers: ["Authorization": "Bearer " + token], configuration: configuration, on: group) { [weak self] socket in
                    let deliver: @Sendable (WebSocket, Data) -> Void = { socket, data in
                        if case .dropped = incoming.yield(data) {
                            incoming.finish(throwing: URLError(.dataLengthExceedsMaximum))
                            _ = socket.close()
                        }
                    }
                    socket.onText { socket, text in deliver(socket, Data(text.utf8)) }
                    socket.onBinary { socket, bytes in deliver(socket, Data(bytes.readableBytesView)) }
                    socket.onClose.whenComplete { _ in
                        Task { @MainActor [weak self] in self?.close(error: URLError(.networkConnectionLost)) }
                    }
                    Task { @MainActor [weak self] in
                        guard let self, !self.closed else { _ = socket.close(); return }
                        self.socket = socket; self.timeout?.cancel(); self.timeout = nil
                        let waiter = self.waiter; self.waiter = nil; waiter?.resume()
                    }
                }.whenFailure { error in
                    Task { @MainActor [weak self] in self?.close(error: error) }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.close() } }
    }

    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        guard let socket, !closed else { completion(URLError(.networkConnectionLost)); return }
        let promise = socket.eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenComplete { result in
            Task { @MainActor in
                switch result { case .success: completion(nil); case .failure(let error): completion(error) }
            }
        }
        socket.send(data, promise: promise)
    }

    func close(error: Error = CancellationError()) {
        guard !closed else { return }; closed = true
        timeout?.cancel(); timeout = nil
        let waiter = waiter; self.waiter = nil; waiter?.resume(throwing: error)
        incoming.finish(throwing: error)
        if let socket { _ = socket.close() }; socket = nil
        group.shutdownGracefully(queue: .global()) { _ in }
    }
}
#endif
