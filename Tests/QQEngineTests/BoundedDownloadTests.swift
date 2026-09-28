#if os(Linux)
import Foundation
import FoundationNetworking
import Testing
@testable import WeChatAIBot

// Exercise libcurl rather than URLProtocol mocks: cancellation and response-size
// limits must hold on real sockets, without contacting any external service.
@Suite(.serialized) struct BoundedDownloadTests {
    @Test(arguments: ["normal", "length", "stream", "cancel", "redirect"])
    func actualHTTPDownloadBoundaries(_ mode: String) async throws {
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", #"""
import http.server, time
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        mode = self.path[1:]
        if mode == 'cancel': time.sleep(5)
        self.send_response(302 if mode == 'redirect' else 200)
        if mode == 'redirect': self.send_header('Location', '/unexpected')
        if mode == 'length': self.send_header('Content-Length', '5000')
        self.end_headers()
        try: self.wfile.write(b'x' * 5000 if mode == 'stream' else b'hello')
        except (BrokenPipeError, ConnectionResetError): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
"""#]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(mode)")!, timeoutInterval: 3)
        let download = Task { try await session.boundedData(for: request, limit: 64) }
        if mode == "cancel" { try await Task.sleep(nanoseconds: 100_000_000); download.cancel() }
        do {
            let (data, response) = try await download.value
            #expect(["normal", "redirect"].contains(mode))
            #expect(data == Data("hello".utf8))
            let expectedStatus = mode == "redirect" ? 302 : 200
            let actualStatus = (response as? HTTPURLResponse)?.statusCode
            #expect(actualStatus == expectedStatus)
        } catch {
            let code = (error as? URLError)?.code
            if mode == "cancel" {
                let cancelled = error is CancellationError || code == URLError.Code.cancelled
                #expect(cancelled)
            } else {
                #expect(["length", "stream"].contains(mode))
                #expect(code == URLError.Code.dataLengthExceedsMaximum)
            }
        }
    }
}
#endif
