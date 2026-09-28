import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One local, authenticated connection. A broken connection cancels all outstanding actions;
/// sends are never retried because a missing acknowledgement is an unknown outcome.
@MainActor final class OneBotConnection {
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    var event: (([String: Any]) -> Void)?
    var disconnected: (() -> Void)?
    func connect(endpoint: String, token: String) throws {
        close()
        guard let url = URL(string: endpoint), !token.isEmpty else { throw AppFailure.message("请先配置 OneBot 令牌") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 1_048_576
        self.socket = socket; socket.resume()
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.socket === socket else { return }
                    let data: Data
                    switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    if let echo = object["echo"] as? String, let continuation = self.pending.removeValue(forKey: echo) {
                        self.deadlines.removeValue(forKey: echo)?.cancel()
                        if object["status"] as? String == "ok", (object["retcode"] as? Int) == 0 {
                            // Lists and objects retain their original shape inside the data field.
                            continuation.resume(returning: object)
                        } else { continuation.resume(throwing: AppFailure.message("OneBot 操作失败，返回码 \(object["retcode"] as? Int ?? -1)")) }
                    } else { self.event?(object) }
                }
            } catch {
                guard let self, self.socket === socket else { return }
                self.close(error: error); self.disconnected?()
            }
        }
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
                socket.send(.data(data)) { [weak self] error in
                    if let error { Task { @MainActor in self?.fail(echo, error: error) } }
                }
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
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        receiver?.cancel(); receiver = nil
        let callbacks = pending.values; pending.removeAll()
        deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        callbacks.forEach { $0.resume(throwing: error ?? AppFailure.message("QQ 连接已关闭；未确认的发送不重试")) }
    }
}
