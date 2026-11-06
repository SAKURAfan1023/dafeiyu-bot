import Foundation

/// Windows uses the packaged Node WebSocket client instead of assuming libcurl supports WebSockets.
/// Only transport frames cross the child boundary; all QQ policy and echo routing remain in Swift.
@MainActor final class NodeOneBotTransport {
    let messages: AsyncThrowingStream<Data, Error>
    private let incoming: AsyncThrowingStream<Data, Error>.Continuation
    private var process: Process?
    private var input: Pipe?
    private var waiter: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private(set) var closed = false
    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        messages = AsyncThrowingStream(bufferingPolicy: .bufferingOldest(32)) { continuation = $0 }
        incoming = continuation
    }
    func connect(url: URL, token: String) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let node = environment["DAFEIYU_NODE"], FileManager.default.isExecutableFile(atPath: node),
              let resources = RuntimeResources.directory else {
            throw AppFailure.message("Windows 后台需要 Node.js，请通过大肥鱼启动器运行或设置 DAFEIYU_NODE")
        }
        let child = Process(), output = Pipe(), input = Pipe()
        child.executableURL = URL(fileURLWithPath: node)
        child.arguments = [resources.appendingPathComponent("QQTransport/onebot.mjs").path]
        child.environment = environment
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        try child.run(); self.process = child; self.input = input
        try? output.fileHandleForWriting.close()
        let handle = output.fileHandleForReading
        DispatchQueue.global().async { [weak self] in
            var buffer = Data()
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let end = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                    let consumed = DispatchSemaphore(value: 0)
                    Task { @MainActor [weak self] in
                        self?.receive(line)
                        consumed.signal()
                    }
                    consumed.wait()
                }
                if buffer.count > 6_300_000 { break }
            }
            try? handle.close()
            Task { @MainActor [weak self] in self?.close(error: URLError(.networkConnectionLost)) }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                    self?.close(error: URLError(.timedOut))
                }
                do { try write(["type": "connect", "url": url.absoluteString, "token": token]) }
                catch { close(error: error) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.close() } }
    }
    private func write(_ value: [String: String]) throws {
        guard let input, !closed else { throw URLError(.networkConnectionLost) }
        var data = try JSONSerialization.data(withJSONObject: value); data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func receive(_ data: Data) {
        guard !closed else { return }
        guard data.count <= 6_300_000,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            close(error: URLError(.dataLengthExceedsMaximum)); return
        }
        if value["type"] == "open" {
            timeout?.cancel(); timeout = nil
            let waiter = self.waiter; self.waiter = nil; waiter?.resume()
        } else if value["type"] == "message", let text = value["data"], text.utf8.count <= 1_048_576 {
            if case .dropped = incoming.yield(Data(text.utf8)) { close(error: URLError(.dataLengthExceedsMaximum)) }
        } else { close(error: URLError(.networkConnectionLost)) }
    }
    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        do { try write(["type": "send", "data": String(decoding: data, as: UTF8.self)]); completion(nil) }
        catch { completion(error) }
    }
    func close(error: Error = CancellationError()) {
        guard !closed else { return }; closed = true
        timeout?.cancel(); timeout = nil
        let waiter = self.waiter; self.waiter = nil; waiter?.resume(throwing: error)
        incoming.finish(throwing: error)
        try? input?.fileHandleForWriting.close(); input = nil
        if let process, process.isRunning { process.terminate() }; process = nil
    }
    deinit { if let process, process.isRunning { process.terminate() } }
}
