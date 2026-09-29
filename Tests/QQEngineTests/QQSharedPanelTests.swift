import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot

@Suite @MainActor struct QQSharedPanelTests {
    private func request(_ server: QQControlServer, action: [String: Any]? = nil, token: String? = nil) async throws -> (Int, [String: Any]) {
        let url = server.controlURL
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(url.port!)/api/\(action == nil ? "status" : "action")")!)
        request.timeoutInterval = 2
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
        let next = try QQControlServer(engine: engine); next.start(announce: false)
        defer { next.stop() }
        #expect(next.controlURL.fragment != oldURL.fragment)
        #expect(try await request(next, token: oldURL.fragment!).0 == 403)
        #expect(try await request(next).0 == 200)
        var oldRequest = URLRequest(url: oldURL); oldRequest.timeoutInterval = 1
        do { _ = try await URLSession.shared.data(for: oldRequest); Issue.record("Closed control port still answered") }
        catch let error as URLError { #expect([.cannotConnectToHost, .networkConnectionLost].contains(error.code)) }
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
        var oldRequest = URLRequest(url: oldURL); oldRequest.timeoutInterval = 1
        do { _ = try await URLSession.shared.data(for: oldRequest); Issue.record("Released server left an accepting port") }
        catch let error as URLError { #expect([.cannotConnectToHost, .networkConnectionLost].contains(error.code)) }
    }
}
