import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One local, authenticated connection. A broken connection cancels all outstanding actions;
/// sends are never retried because a missing acknowledgement is an unknown outcome.
@MainActor final class OneBotConnection {
    #if os(Linux)
    private var socket: LinuxOneBotTransport?
    #else
    private var socket: URLSessionWebSocketTask?
    #endif
    private var receiver: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    var event: (([String: Any]) -> Void)?
    var disconnected: ((Error) -> Void)?
    func connect(endpoint: String, token: String) async throws {
        close()
        guard let url = URL(string: endpoint), !token.isEmpty else { throw AppFailure.message("请先配置 OneBot 令牌") }
        #if os(Linux)
        let socket = LinuxOneBotTransport()
        self.socket = socket
        do { try await socket.connect(url: url, token: token) }
        catch { if self.socket === socket { close(error: error) }; throw error }
        guard self.socket === socket else { socket.close(); throw CancellationError() }
        #else
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 1_048_576
        self.socket = socket; socket.resume()
        #endif
        receiver = Task { [weak self] in
            do {
                #if os(Linux)
                for try await data in socket.messages {
                    guard let self, self.socket === socket else { return }
                    guard !socket.closed else { throw URLError(.networkConnectionLost) }
                    try self.receive(data)
                }
                #else
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.socket === socket else { return }
                    let data: Data
                    switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                    try self.receive(data)
                }
                #endif
            } catch {
                guard let self, self.socket === socket else { return }
                self.close(error: error); self.disconnected?(error)
            }
        }
    }
    private func receive(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let echo = object["echo"] as? String, let continuation = pending.removeValue(forKey: echo) {
            deadlines.removeValue(forKey: echo)?.cancel()
            if object["status"] as? String == "ok", (object["retcode"] as? Int) == 0 {
                // Lists and objects retain their original shape inside the data field.
                continuation.resume(returning: object)
            } else { continuation.resume(throwing: AppFailure.message("OneBot 操作失败，返回码 \(object["retcode"] as? Int ?? -1)")) }
        } else { event?(object) }
    }
    func action(_ name: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard let socket else { throw AppFailure.message("QQ 未连接") }
        try Task.checkCancellation()
        let echo = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["action": name, "params": params, "echo": echo])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[echo] = continuation
                deadlines[echo] = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                    self?.fail(echo, error: AppFailure.message("OneBot 响应超时；如已提交发送，结果未知且不重发"))
                }
                let completion: (Error?) -> Void = { [weak self] error in
                    if let error { Task { @MainActor in self?.fail(echo, error: error) } }
                }
                #if os(Linux)
                socket.send(data, completion: completion)
                #else
                socket.send(.data(data), completionHandler: completion)
                #endif
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fail(echo, error: CancellationError()) }
        }
    }
    private func fail(_ echo: String, error: Error) {
        deadlines.removeValue(forKey: echo)?.cancel()
        pending.removeValue(forKey: echo)?.resume(throwing: error)
    }
    func close(error: Error? = nil) {
        #if os(Linux)
        socket?.close()
        #else
        socket?.cancel(with: .goingAway, reason: nil)
        #endif
        socket = nil
        receiver?.cancel(); receiver = nil
        let callbacks = pending.values; pending.removeAll()
        deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        callbacks.forEach { $0.resume(throwing: error ?? AppFailure.message("QQ 连接已关闭；未确认的发送不重试")) }
    }
}
