import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite @MainActor struct QQSharedPanelTests {
    private func requireClosedPort(_ url: URL) async throws {
        // Corelibs URLSession can report .unknown for a closed loopback socket.
        // Check TCP refusal directly; arbitrary errors/timeouts are not success.
        try #require(url.host == "127.0.0.1")
        let port = try #require(url.port.flatMap(UInt16.init(exactly:)))
        let deadline = Date().addingTimeInterval(1)
        repeat {
            #if os(Linux)
            let socket = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
            #else
            let socket = socket(AF_INET, SOCK_STREAM, 0)
            #endif
            try #require(socket >= 0)
            defer { close(socket) }
            try #require(fcntl(socket, F_SETFL, O_NONBLOCK) == 0)
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if result < 0 {
                let code = errno
                if code == ECONNREFUSED { return }
                // Cancelling the listener may reset an in-flight handshake.
                // Retry that transition; only a later refusal proves closure.
                if code != ECONNRESET {
                    try #require(code == EINPROGRESS, "Unexpected connect errno: \(code)")
                    var descriptor = pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)
                    let ready = poll(&descriptor, 1, 100)
                    try #require(ready >= 0)
                    if ready > 0 {
                        var error: Int32 = 0, length = socklen_t(MemoryLayout<Int32>.size)
                        try #require(getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &length) == 0)
                        if error == ECONNREFUSED { return }
                        try #require(error == 0 || error == ECONNRESET, "Unexpected socket error: \(error)")
                    }
                }
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        Issue.record("Closed control port did not refuse TCP connections within one second")
    }

    private func request(_ server: QQControlServer, action: [String: Any]? = nil, token: String? = nil) async throws -> (Int, [String: Any]) {
        let url = server.controlURL
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(url.port!)/api/\(action == nil ? "status" : "action")")!)
        // Other integration suites start Python fixtures on MainActor in parallel.
        // This is a functional check, not a two-second latency budget. Allow the
        // server's existing request window; closed-port checks below stay strict.
        request.timeoutInterval = 15
        request.setValue(token ?? url.fragment!, forHTTPHeaderField: "X-QQ-Control")
        request.setValue("http://127.0.0.1:\(url.port!)", forHTTPHeaderField: "Origin")
        if let action {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: action)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    @Test func nativeAndWebShareConfigurationAndRejectStaleEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        engine.save(expectedSelfID: "12345")
        let server = try QQControlServer(engine: engine); server.start(announce: false)
        defer { server.stop() }
        let (code, initial) = try await request(server)
        #expect(code == 200 && server.isRunning)
        let oldRevision = try #require(initial["configurationRevision"] as? String)
        // Native saves through the same engine that owns the live Web surface.
        engine.save(endpoint: "ws://127.0.0.1:3199")
        let (_, current) = try await request(server)
        #expect((current["config"] as? [String: Any])?["endpoint"] as? String == engine.config.endpoint)
        let (_, stale) = try await request(server, action: ["action":"saveConnection", "configurationRevision":oldRevision, "endpoint":"ws://127.0.0.1:3188"])
        #expect(!(stale["error"] as? String ?? "").isEmpty)
        #expect(engine.config.endpoint == "ws://127.0.0.1:3199")
        let revision = try #require(current["configurationRevision"] as? String)
        let (_, saved) = try await request(server, action: ["action":"saveConnection", "configurationRevision":revision, "endpoint":"ws://127.0.0.1:3177"])
        #expect(saved["error"] as? String == "")
        #expect(engine.config.endpoint == "ws://127.0.0.1:3177")
        let reopened = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(reopened.config == engine.config)
        #expect(!engine.connected && !engine.running && engine.usage.calls == 0 && engine.sends.attempts == 0)
    }

    @Test func closingSurfaceRevokesAccessButPreservesEngineAndCredentials() async throws {
        let engine = QQEngine(preview: true, allowAuthenticationUI: false)
        #expect(engine.useTemporaryCredentials(token: "synthetic-token", key: "synthetic-key"))
        var server: QQControlServer? = try QQControlServer(engine: engine)
        weak var released = server
        let oldURL = server!.controlURL
        server!.start(announce: false); server!.start(announce: false)
        #expect(try await request(server!).0 == 200)
        server!.stop(); server!.stop()
        #expect(!server!.isRunning && engine.usesTemporaryCredentials)
        #expect(engine.status == "临时凭证已就绪，仅在本次应用运行期间使用")
        // A stopped object cannot resurrect its old token/listener.
        server!.start(announce: false); #expect(!server!.isRunning)
        server = nil
        #expect(released == nil)
        try await requireClosedPort(oldURL)
        let next = try QQControlServer(engine: engine); next.start(announce: false)
        defer { next.stop() }
        #expect(next.controlURL.fragment != oldURL.fragment)
        #expect(try await request(next, token: oldURL.fragment!).0 == 403)
        #expect(try await request(next).0 == 200)
    }

    @Test func unstartedSurfaceCanBeStoppedAndReleased() {
        let engine = QQEngine(preview: true, allowAuthenticationUI: false)
        var server: QQControlServer? = try? QQControlServer(engine: engine)
        #expect(server != nil)
        weak var released = server
        server?.stop(); server = nil
        #expect(released == nil)
    }

    @Test func droppingActiveSurfaceReleasesItsListener() async throws {
        let engine = QQEngine(preview: true, allowAuthenticationUI: false)
        var server: QQControlServer? = try QQControlServer(engine: engine)
        weak var released = server
        let oldURL = server!.controlURL
        server!.start(announce: false)
        #expect(try await request(server!).0 == 200)
        server = nil
        // In-flight HTTP completion may briefly retain its handler task.
        for _ in 0..<20 where released != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(released == nil)
        try await requireClosedPort(oldURL)
    }

    @Test func closingAndReopeningWebPreservesRunningEngineUntilExplicitPause() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py")
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixture.path, directory.path]; process.standardOutput = output
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        // Do not block the control server's MainActor while Python starts.
        let line = await Task.detached {
            String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
        let port = try #require(Int(line))
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        defer { engine.disconnect() }
        engine.save(endpoint: "ws://127.0.0.1:\(port)", expectedSelfID: "12345")
        try #require(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect(); try #require(engine.connected, "\(engine.error ?? engine.status)")
        engine.add(try #require(engine.contacts.first { !$0.group }))
        engine.saveReplySettings(ai: engine.config.ai, persona: engine.config.effectivePersona, enabledTargets: ["private:54321"])
        engine.start(duration: 120); try #require(engine.running, "\(engine.error ?? engine.status)")
        let deadline = try #require(engine.runDeadline)
        // No ready marker is written: the synthetic peer emits no messages.
        let server = try QQControlServer(engine: engine); server.start(announce: false)
        defer { server.stop() }
        #expect(try await request(server).1["running"] as? Bool == true)
        server.stop()
        #expect(engine.running && engine.connected && engine.usesTemporaryCredentials)
        #expect(engine.runDeadline == deadline)
        try await requireClosedPort(server.controlURL)
        let reopened = try QQControlServer(engine: engine); reopened.start(announce: false)
        defer { reopened.stop() }
        #expect(reopened.controlURL.fragment != server.controlURL.fragment)
        #expect(try await request(reopened).1["running"] as? Bool == true)
        #expect(engine.runDeadline == deadline)
        let (_, paused) = try await request(reopened, action: ["action":"pause"])
        #expect(paused["running"] as? Bool == false)
        #expect(!engine.running && engine.connected && engine.runDeadline == nil && engine.queuedCount == 0)
        #expect(engine.usage.calls == 0 && engine.sends.attempts == 0)
        let actions = try String(contentsOf: directory.appendingPathComponent("actions"), encoding: .utf8)
        #expect(!actions.contains("send_private_msg") && !actions.contains("send_group_msg"))
    }
}
