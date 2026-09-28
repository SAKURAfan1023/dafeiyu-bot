#if os(Linux)
import Foundation
import FoundationNetworking

// FoundationNetworking lacks AsyncBytes in the supported toolchain. The delegate
// enforces the same limit while receiving, not after allocating an unbounded body.
private final class BoundedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let limit: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var data = Data()
    private var response: URLResponse?
    private var oversized = false
    init(limit: Int) { self.limit = limit }
    func start(configuration: URLSessionConfiguration, request: URLRequest, continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        lock.lock(); defer { lock.unlock() }
        if cancelled { continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session; let task = session.dataTask(with: request); self.task = task; task.resume()
    }
    func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        oversized = response.expectedContentLength > limit
        completionHandler(oversized ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        guard !oversized, bytes.count <= limit - data.count else { oversized = true; dataTask.cancel(); return }
        data.append(bytes)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let callback = continuation; continuation = nil; self.session = nil; self.task = nil; lock.unlock()
        session.finishTasksAndInvalidate()
        if oversized { callback?.resume(throwing: URLError(.dataLengthExceedsMaximum)) }
        else if let error { callback?.resume(throwing: error) }
        else if let response { callback?.resume(returning: (data, response)) }
        else { callback?.resume(throwing: URLError(.badServerResponse)) }
    }
}

extension URLSession {
    func boundedData(for request: URLRequest, limit: Int) async throws -> (Data, URLResponse) {
        let download = BoundedDownload(limit: limit)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.start(configuration: configuration, request: request, continuation: continuation)
            }
        } onCancel: { download.cancel() }
    }
}
#endif
