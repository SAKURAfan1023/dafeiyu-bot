import Foundation
import Testing
import BotCore
@testable import WeChatAIBot

private final class VisualFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var mode = "ok"
    private static var requests: [URLRequest] = []
    static func reset(_ value: String) { lock.lock(); defer { lock.unlock() }; mode = value; requests = [] }
    static var captured: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var copy = request
        if let stream = copy.httpBodyStream, copy.httpBody == nil {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }; copy.httpBody = data
        }
        Self.lock.lock(); Self.requests.append(copy); let mode = Self.mode; Self.lock.unlock()
        if mode == "hold" && request.url?.host == "open.bigmodel.cn" { return }
        if request.url?.host == "gchat.qpic.cn" {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mode == "unread" ? Data("not an image".utf8) : try! QQIncomingImagesTests.animatedFixture()); client?.urlProtocolDidFinishLoading(self); return
        }
        let content = "{\"description\":\"蓝色圆点\",\"visibleText\":\"\",\"motion\":\"向右移动\",\"emotionCandidates\":\"无明确情绪\",\"uncertainty\":\"无\"}"
        var object: [String: Any] = request.url!.host == "vision.googleapis.com" ? ["responses": [["webDetection": ["bestGuessLabels": [["label": "blue circle"]]]]]] : ["choices": [["finish_reason": mode == "length" ? "length" : "stop", "message": ["content": mode == "badJSON" ? "not json" : content]]]]
        if request.url?.host == "api.deepseek.com" {
            var answer: [String: Any] = ["text": "蓝色圆点向右移动了。", "emotion": "neutral", "intensity": 0]
            if String(decoding: copy.httpBody ?? Data(), as: UTF8.self).contains("[QQ_PARTICIPATION]") { answer["participate"] = true }
            object = ["choices": [["finish_reason": "stop", "message": ["content": String(decoding: try! JSONSerialization.data(withJSONObject: answer), as: UTF8.self)]]]]
        }
        let capacity = mode == "capacity" && String(decoding: copy.httpBody ?? Data(), as: UTF8.self).contains("glm-4.6v-flash")
        if capacity { object = ["error": ["code": "1305"]] }
        if mode == "error200" { object = ["responses": [["error": ["code": 7]]], "error": ["code": 7]] }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: capacity ? 429 : mode == "denied" ? 403 : 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object)); client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) @MainActor struct QQVisualToolsTests {
    private func session(_ mode: String) -> URLSession {
        VisualFixture.reset(mode); let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [VisualFixture.self]; return URLSession(configuration: config)
    }
    @Test func googleRanksEvidenceAndDoesNotConfuseErrorsWithNoMatches() throws {
        let result = try QQVisualTools.searchResult(["responses": [["webDetection": ["pagesWithMatchingImages": [
            ["url": "https://example.com/partial", "pageTitle": "partial", "partialMatchingImages": [["url": "https://example.com/a"]]],
            ["url": "http://127.0.0.1/private", "fullMatchingImages": [["url": "x"]]],
            ["url": "https://example.org/full", "pageTitle": "<b>full</b>", "fullMatchingImages": [["url": "https://example.org/b"]]]
        ], "webEntities": [["description": "candidate", "score": 1.5]]]]]])
        #expect(result.sources == ["https://example.org/full", "https://example.com/partial"])
        #expect(result.image == nil); #expect(!result.content.contains("127.0.0.1")); #expect(!result.content.contains("<b>"))
        let empty = try QQVisualTools.searchResult(["responses": [[:]]]); #expect(empty.sources.isEmpty); #expect(empty.content.contains("未返回匹配"))
        for object: [String: Any] in [[:], ["responses": []], ["responses": [["error": ["code": 7]]]]] {
            #expect(throws: (any Error).self) { try QQVisualTools.searchResult(object) }
        }
        #expect(QQVisualTools.wantsWebSearch("用谷歌搜图，查这个角色出处"))
        #expect(!QQVisualTools.wantsWebSearch("哈哈，晚安啦"))
    }
    @Test(arguments: ["ok", "capacity", "length", "badJSON", "error200", "denied"]) func officialRequestsAreBoundedAndAuthenticated(_ mode: String) async throws {
        let session = session(mode); defer { session.invalidateAndCancel() }
        let frames = try QQIncomingImages.frames(QQIncomingImagesTests.animatedFixture())
        do {
            let text = try await QQVisualTools(session: session).describe(images: frames, context: "合成动图", key: "synthetic-zhipu")
            #expect(["ok", "capacity"].contains(mode)); #expect(text.contains("向右移动"))
            #expect(VisualFixture.captured.count == (mode == "capacity" ? 2 : 1))
        } catch { #expect(!["ok", "capacity"].contains(mode)) }
        let request = try #require(VisualFixture.captured.first)
        #expect(request.url?.host == "open.bigmodel.cn")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-zhipu")
        let body = try #require(request.httpBody); #expect(!String(decoding: body, as: UTF8.self).contains("synthetic-zhipu"))
        let parsed = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(parsed["model"] as? String == "glm-4.6v-flash")
        if mode == "ok" {
            _ = try await QQVisualTools(session: session).search(image: frames[0], key: "synthetic-google")
            let google = try #require(VisualFixture.captured.last)
            #expect(google.url?.absoluteString == "https://vision.googleapis.com/v1/images:annotate")
            #expect(google.value(forHTTPHeaderField: "X-Goog-Api-Key") == "synthetic-google")
            #expect(google.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }
    @Test func cancellationAndMissingKeysDoNotProduceObservations() async throws {
        let session = session("hold"); defer { session.invalidateAndCancel() }
        let tool = QQVisualTools(session: session), frame = try #require(QQIncomingImages.frames(QQIncomingImagesTests.animatedFixture()).first)
        let missing = try await tool.search(image: frame, key: ""); #expect(missing.sources.isEmpty); #expect(VisualFixture.captured.isEmpty)
        let task = Task { try await tool.describe(images: [frame], context: "synthetic", key: "fixture") }
        for _ in 0..<100 where VisualFixture.captured.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        task.cancel()
        do { _ = try await task.value; Issue.record("cancelled request returned observation") } catch {}
    }
    @Test func fallbackReservesQuotaBeforeSecondRequest() async throws {
        let session = session("capacity"); defer { session.invalidateAndCancel() }
        let frame = try #require(QQIncomingImages.frames(QQIncomingImagesTests.animatedFixture()).first)
        actor Budget { var calls = 0; func reserve() throws { calls += 1; if calls > 1 { throw CancellationError() } } }
        let budget = Budget()
        do {
            _ = try await QQVisualTools(session: session).describe(images: [frame], context: "synthetic", key: "fixture", beforeAttempt: { try await budget.reserve() })
            Issue.record("quota exhaustion should cancel fallback")
        } catch is CancellationError {} catch { Issue.record("unexpected error") }
        #expect(VisualFixture.captured.count == 1)
    }
    @Test func visualSecretsNeverEnterConfigOrStoredState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        var config = QQVisualConfig(); config.provider = .zhipu; config.googleWebEnabled = true
        engine.saveVisualTools(config, googleKey: "synthetic-google-secret", persistCredentials: false)
        #expect(engine.error == nil); #expect(engine.hasGoogleVisionKey)
        let state = try String(contentsOf: directory.appendingPathComponent("qq-state.json"))
        #expect(state.contains("zhipu")); #expect(!state.contains("synthetic-google-secret"))
        #expect(QQConfig().effectiveVisualTools.provider == .deepseek)
        #expect(!QQConfig().effectiveVisualTools.googleWebEnabled)
    }
    @Test(arguments: ["ok", "hold", "quota", "proactive", "unread"]) func actualEngineRoutesGIFThroughVisionAndCancelsSafely(_ mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data((["proactive", "unread"].contains(mode) ? "groupParticipation" : "groupVisual").utf8).write(to: directory.appendingPathComponent("message-shape"))
        try Data("1".utf8).write(to: directory.appendingPathComponent("message-count"))
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path, directory.path]
        server.standardOutput = output; server.standardError = FileHandle.nullDevice
        try server.run(); defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let session = session(mode); defer { session.invalidateAndCancel() }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session), incomingImageLoader: QQIncomingImages(session: session))
        defer { engine.disconnect() }
        engine.config.expectedSelfID = "12345"; engine.config.endpoint = "ws://127.0.0.1:\(port)"
        var visual = QQVisualConfig(); visual.provider = .zhipu; visual.googleWebEnabled = true
        engine.saveVisualTools(visual, googleKey: "synthetic-google", persistCredentials: false)
        engine.saveImageGeneration(QQImageGenerationConfig(), zhipuKey: "synthetic-zhipu", cloudflareToken: "", persistCredentials: false)
        engine.config.effectiveVisionEnabled = true; engine.config.effectiveOnlineEnabled = true
        if mode == "quota" { engine.config.ai.dailyLimit = 1 }
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic"))
        await engine.connect(); try #require(engine.connected)
        engine.add(try #require(engine.contacts.first(where: { $0.group }))); engine.config.targets[0].enabled = true
        engine.config.effectiveGroupParticipationEnabled = ["proactive", "unread"].contains(mode)
        engine.config.effectiveGroupParticipationEvery = 2
        engine.start(singleReply: true); try #require(engine.running)
        if ["proactive", "unread"].contains(mode) {
            let rows: [[String: Any]] = (1...2).map { id in
                ["post_type": "message", "self_id": 12345, "user_id": 54321, "sender": ["user_id": 54321], "message_type": "group", "sub_type": "normal", "group_id": 99999, "message_id": id,
                 "message": id == 1 ? [["type": "image", "data": ["file": "synthetic.gif", "url": "https://gchat.qpic.cn/fixture"]]] : [["type": "text", "data": ["text": "这个圆点往哪个方向动了？"]]]]
            }
            try JSONSerialization.data(withJSONObject: rows).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
        } else { try Data().write(to: directory.appendingPathComponent("ready")) }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if mode == "hold" && VisualFixture.captured.contains(where: { $0.url?.host == "open.bigmodel.cn" }) { engine.pause(); break }
            if mode == "unread" && engine.logs.contains(where: { $0.detail.contains("紧邻媒体") }) { break }
            if mode == "quota" && engine.logs.contains(where: { $0.state == .failed }) { break }
            if engine.sends.confirmed == 1 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let requests = VisualFixture.captured
        if mode == "ok" || mode == "proactive" {
            #expect(engine.sends.confirmed == 1); #expect(engine.usage.calls == (mode == "proactive" ? 3 : 4))
            if mode == "proactive" { #expect(!requests.contains { $0.url?.host == "vision.googleapis.com" }) }
            let vision = try #require(requests.first(where: { $0.url?.host == "open.bigmodel.cn" })?.httpBody)
            #expect(String(decoding: vision, as: UTF8.self).components(separatedBy: "image_url").count > 6)
            let deepseek = requests.filter { $0.url?.host == "api.deepseek.com" }
            #expect(deepseek.count == 2)
            for request in deepseek {
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                #expect(body.contains("向右移动")); #expect(!body.contains("data:image")); #expect(!body.contains("synthetic-google"))
            }
            let payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("payload"))) as? [String: Any])
            let segments = try #require(payload["message"] as? [[String: Any]])
            #expect(segments.count == 1); #expect(segments[0]["type"] as? String == "text")
        } else {
            #expect(engine.sends.attempts == 0)
            #expect(!requests.contains { $0.url?.host == "api.deepseek.com" })
            if mode == "quota" { #expect(!requests.contains { $0.url?.host == "open.bigmodel.cn" }) }
        }
    }

}
