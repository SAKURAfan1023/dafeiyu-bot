import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot

private final class ImageProviderFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var mode = "success"
    private static var requests: [URLRequest] = []
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=")!
    static func reset(_ value: String) { lock.lock(); defer { lock.unlock() }; mode = value; requests = [] }
    static var captured: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
            captured.httpBody = data
        }
        Self.lock.lock(); Self.requests.append(captured); let mode = Self.mode; Self.lock.unlock()
        let host = request.url!.host!
        var status = 200, object: [String: Any] = [:]
        var data: Data?
        if host == "api.deepseek.com" {
            let body = try! JSONSerialization.jsonObject(with: captured.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: Any]]
            let tools = body["tools"] as? [[String: Any]] ?? []
            let generationOffered = tools.contains { ($0["function"] as? [String: Any])?["name"] as? String == "generate_image" }
            if messages.contains(where: { ($0["content"] as? String)?.contains("[IMAGE_PROMPT_PLAN]") == true }) {
                let plan = mode == "planDecline" ? "{\"action\":\"decline\",\"prompt\":\"\",\"note\":\"可以画完整日常着装的成年角色\"}" : "{\"action\":\"generate\",\"prompt\":\"成年蓝发动漫女性，人类面孔，完整日常着装，鲸鱼尾巴\",\"note\":\"\"}"
                object = ["choices": [["message": ["content": plan], "finish_reason": "stop"]], "usage": ["total_tokens": 1]]
            } else if generationOffered && !messages.contains(where: { $0["role"] as? String == "tool" }) {
                let calls: [[String: Any]] = (mode == "duplicate" ? ["generate_image", "search_images"] : ["generate_image"]).enumerated().map { i, name in
                    ["id": "call-\(i)", "type": "function", "function": ["name": name, "arguments": name == "generate_image" ? "{\"prompt\":\"a cute adult whale girl\"}" : "{\"query\":\"cat\"}"]]
                }
                object = ["choices": [["message": ["content": "", "reasoning_content": "synthetic", "tool_calls": calls], "finish_reason": "tool_calls"]], "usage": ["total_tokens": 1]]
            } else {
                object = ["choices": [["message": ["content": "{\"text\":\"画好啦，看看。\",\"emotion\":\"joy\",\"intensity\":1}", "reasoning_content": "synthetic"], "finish_reason": "stop"]], "usage": ["total_tokens": 1]]
            }
        } else if host == "open.bigmodel.cn" {
            if mode == "hold" { return }
            if mode == "timeout" { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
            if ["fallback", "bothFail", "quota"].contains(mode) { status = 429; object = ["error": ["code": "1302", "message": "rate limit"]] }
            else if ["refusal", "refusal200"].contains(mode) { status = mode == "refusal" ? 400 : 200; object = ["error": ["code": "1301", "message": "blocked"]] }
            else if mode == "unknown403" { status = 403; object = ["error": ["code": "unknown", "message": "forbidden"]] }
            else if mode == "filtered" { object = ["content_filter": [["role": "assistant", "level": 0]], "data": [["url": "https://sfile.chatglm.cn/fixture.png"]]] }
            else if mode == "malformed" { object = [:] }
            else if mode == "falseSuccess" { object = ["success": false] }
            else { object = ["data": [["url": mode == "badURL" ? "http://127.0.0.1/secret" : "https://maas-watermark-prod-new.cn-wlcb.ufileos.com/fixture.png"]]] }
        } else if host == "api.cloudflare.com" {
            if ["bothFail", "reverse"].contains(mode) { status = 503; object = ["success": false, "errors": [["code": 3040, "message": "busy"]]] }
            else { object = ["success": true, "result": ["image": Self.png.base64EncodedString()]] }
        } else if host == "maas-watermark-prod-new.cn-wlcb.ufileos.com" { data = mode == "invalidImage" ? Data("not an image".utf8) : Self.png }
        else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data ?? (try! JSONSerialization.data(withJSONObject: object)))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) @MainActor struct QQImageGeneratorTests {
    private func session(_ mode: String) -> URLSession {
        ImageProviderFixture.reset(mode)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ImageProviderFixture.self]
        return URLSession(configuration: config)
    }
    private var settings: QQImageGenerationConfig {
        var value = QQImageGenerationConfig(); value.enabled = true; value.cloudflareAccountID = String(repeating: "a", count: 32); return value
    }
    private let credentials = QQImageCredentials(zhipuKey: "synthetic-zhipu", cloudflareToken: "synthetic-cloudflare")

    @Test func imagePlansRequireBoundedTypedDecisions() throws {
        #expect(try QQImagePromptPlan.decode("{\"action\":\"generate\",\"prompt\":\"成年动漫角色\",\"note\":\"\"}").action == .generate)
        #expect(try QQImagePromptPlan.decode("{\"action\":\"none\",\"prompt\":\"\",\"note\":\"\"}").action == .none)
        for invalid in ["{}", #"{"action":"generate","prompt":" ","note":""}"#, #"{"action":"decline","prompt":"still generate","note":""}"#, #"{"action":"retry","prompt":"","note":""}"#] {
            #expect(throws: (any Error).self) { try QQImagePromptPlan.decode(invalid) }
        }
    }
    @Test(arguments: ["success", "fallback", "timeout", "malformed", "falseSuccess", "invalidImage", "badURL", "bothFail", "reverse", "refusal", "refusal200", "filtered", "unknown403"])
    func providerFallbackUsesOfficialSchemasAndPreservesRefusals(mode: String) async throws {
        let session = session(mode); defer { session.invalidateAndCancel() }
        var config = settings; if mode == "reverse" { config.primary = .cloudflare }
        var attempts = 0
        let result = try await QQImageGenerator(session: session).execute(arguments: "{\"prompt\":\"cute whale\"}", settings: config, credentials: credentials, beforeAttempt: { attempts += 1 })
        let terminal = ["refusal", "refusal200", "filtered", "unknown403"].contains(mode)
        #expect((result.image != nil) == (!terminal && mode != "bothFail"))
        #expect(attempts == (mode == "success" || terminal ? 1 : 2))
        let requests = ImageProviderFixture.captured
        #expect(requests.allSatisfy { ["open.bigmodel.cn", "api.cloudflare.com", "maas-watermark-prod-new.cn-wlcb.ufileos.com"].contains($0.url!.host!) })
        for r in requests where r.url?.host == "maas-watermark-prod-new.cn-wlcb.ufileos.com" { #expect(r.value(forHTTPHeaderField: "Authorization") == nil) }
        for r in requests where r.url?.host == "open.bigmodel.cn" {
            let body = try #require(JSONSerialization.jsonObject(with: r.httpBody!) as? [String: Any])
            #expect(body["model"] as? String == "cogview-3-flash")
            #expect(body["watermark_enabled"] as? Bool == true)
            #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-zhipu")
        }
        #expect(!result.content.contains("synthetic-zhipu")); #expect(!result.content.contains("synthetic-cloudflare"))
        if result.image != nil { #expect(result.image == ImageProviderFixture.png); #expect(result.sources.first?.hasPrefix("AI 生成") == true) }
    }
    @Test func disabledInvalidMissingKeysAndFallbackOffDoNotSpendUnexpectedly() async throws {
        let session = session("fallback"); defer { session.invalidateAndCancel() }
        var attempts = 0, config = settings
        config.enabled = false
        _ = try await QQImageGenerator(session: session).execute(arguments: "{}", settings: config, credentials: credentials, beforeAttempt: { attempts += 1 })
        config.enabled = true
        for input in ["{}", "{\"prompt\":\"https://example.com/secret\"}", "{\"prompt\":\"x\",\"url\":\"x\"}"] {
            _ = try await QQImageGenerator(session: session).execute(arguments: input, settings: config, credentials: credentials, beforeAttempt: { attempts += 1 })
        }
        #expect(ImageProviderFixture.captured.isEmpty); #expect(attempts == 0)
        config.fallbackEnabled = false
        let failed = try await QQImageGenerator(session: session).execute(arguments: "{\"prompt\":\"cat\"}", settings: config, credentials: credentials, beforeAttempt: { attempts += 1 })
        #expect(failed.image == nil); #expect(attempts == 1)
        config.fallbackEnabled = true
        let result = try await QQImageGenerator(session: session).execute(arguments: "{\"prompt\":\"cat\"}", settings: config, credentials: QQImageCredentials(cloudflareToken: "synthetic-cloudflare"), beforeAttempt: { attempts += 1 })
        #expect(result.image != nil); #expect(attempts == 2)
    }
    @Test func quotaOrScopeFailureDoesNotBecomeProviderFailover() async throws {
        let session = session("fallback"); defer { session.invalidateAndCancel() }
        var attempts = 0
        do {
            _ = try await QQImageGenerator(session: session).execute(arguments: "{\"prompt\":\"cat\"}", settings: settings, credentials: credentials, beforeAttempt: {
                attempts += 1; if attempts == 2 { throw CancellationError() }
            })
            Issue.record("Expected cancellation")
        } catch is CancellationError {} catch { Issue.record("Unexpected error") }
        #expect(ImageProviderFixture.captured.count == 1)
    }
    @Test func legacyConfigurationDefaultsToDisabledAndRejectsInvalidAccount() throws {
        var config = QQConfig(); config.expectedSelfID = "12345"
        let encoded = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(QQConfig.self, from: encoded)
        #expect(!restored.effectiveImageGeneration.enabled)
        #expect(restored.effectiveImageGeneration.primary == .zhipu)
        var images = settings; images.cloudflareAccountID = "../../other-account"
        #expect(throws: (any Error).self) { try images.validate() }
    }
    @Test func imageCredentialsStayOutOfPersistedState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        engine.config.expectedSelfID = "12345"
        engine.saveImageGeneration(settings, zhipuKey: credentials.zhipuKey, cloudflareToken: credentials.cloudflareToken, persistCredentials: false)
        #expect(engine.error == nil); #expect(engine.hasZhipuImageKey && engine.hasCloudflareImageToken)
        let stored = try String(contentsOf: directory.appendingPathComponent("qq-state.json"))
        #expect(!stored.contains(credentials.zhipuKey)); #expect(!stored.contains(credentials.cloudflareToken))
        let reloaded = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(reloaded.config.effectiveImageGeneration == settings)
        #expect(!reloaded.hasZhipuImageKey && !reloaded.hasCloudflareImageToken)
        engine.clearTemporaryCredentials(); #expect(!engine.hasZhipuImageKey && !engine.hasCloudflareImageToken)
    }
    @Test func generationAndSearchShareOneImageBudgetAndSurviveSemanticReview() async throws {
        let session = session("duplicate"); defer { session.invalidateAndCancel() }
        var invoked: [String] = []
        let result = try await DeepSeekClient(session: session).reviewedQQReply(key: "synthetic", config: QQConfig().ai,
            rule: ChatRule(name: "fixture"), history: [], text: "draw a whale", toolHandler: { name, arguments in
                invoked.append(name)
                return try await QQImageGenerator(session: session).execute(arguments: arguments, settings: self.settings, credentials: self.credentials, beforeAttempt: {})
            }, imageGenerationEnabled: true, reserve: {})
        #expect(invoked == ["generate_image"])
        #expect(result.image == ImageProviderFixture.png)
        #expect(result.imageStatus?.contains("生成成功") == true)
        #expect(result.sources == ["AI 生成 · 智谱 CogView-3-Flash"])
        #expect(result.usedTools)
    }
    @Test(arguments: ["fallback", "hold", "quota", "planDecline", "proactive"])
    func realEngineSendsGeneratedImageOrCancelsBeforeBackup(mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("1".utf8).write(to: directory.appendingPathComponent("message-count"))
        try Data((mode == "proactive" ? "groupImagePrompt" : "imagePrompt").utf8).write(to: directory.appendingPathComponent("message-shape"))
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py")
        let server = Process(), output = Pipe(); server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [fixture.path, directory.path]; server.standardOutput = output
        try server.run(); defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let session = session(mode); defer { session.invalidateAndCancel() }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session), imageGenerator: QQImageGenerator(session: session))
        defer { engine.disconnect() }
        engine.config.expectedSelfID = "12345"; engine.config.endpoint = "ws://127.0.0.1:\(port)"
        engine.saveImageGeneration(settings, zhipuKey: credentials.zhipuKey, cloudflareToken: credentials.cloudflareToken, persistCredentials: false)
        if mode == "quota" { engine.config.ai.dailyLimit = 2 }
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic"))
        await engine.connect(); try #require(engine.connected, "\(engine.error ?? engine.status)")
        engine.add(try #require(engine.contacts.first(where: { $0.group == (mode == "proactive") }))); engine.config.targets[0].enabled = true
        if mode == "proactive" { engine.config.effectiveGroupParticipationEnabled = true; engine.config.effectiveGroupParticipationEvery = 1 }
        engine.start(singleReply: true); try #require(engine.running)
        try Data().write(to: directory.appendingPathComponent("ready"))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if mode == "hold" && ImageProviderFixture.captured.contains(where: { $0.url?.host == "open.bigmodel.cn" }) { engine.pause(); break }
            if mode == "quota" && engine.logs.contains(where: { $0.state == .failed }) { break }
            if engine.sends.confirmed == 1 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let captured = ImageProviderFixture.captured
        #expect(captured.first?.url?.host == "api.deepseek.com")
        #expect(captured.first?.httpBody.map { String(decoding: $0, as: UTF8.self).contains("IMAGE_PROMPT_PLAN") } == true)
        for request in captured where request.url?.host == "open.bigmodel.cn" {
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect((body["prompt"] as? String)?.contains("人类面孔") == true)
        }
        if ["fallback", "proactive"].contains(mode) {
            #expect(engine.sends.confirmed == 1); #expect(!engine.running)
            #expect(engine.usage.calls == (mode == "proactive" ? 4 : 5)) // Intent planning, primary, backup, answer, semantic review.
            #expect(engine.imageGenerationStatus.contains(mode == "proactive" ? "生成成功" : "已切换备用"))
            let payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("payload"))) as? [String: Any])
            let segments = try #require(payload["message"] as? [[String: Any]])
            #expect(segments.count == 2)
            #expect((segments[1]["data"] as? [String: String])?["file"] == "base64://" + ImageProviderFixture.png.base64EncodedString())
            #expect((segments[0]["data"] as? [String: String])?["text"]?.contains(mode == "proactive" ? "AI 生成 · 智谱" : "AI 生成 · Cloudflare") == true)
        } else if mode == "planDecline" {
            #expect(engine.sends.confirmed == 1); #expect(engine.usage.calls == 3)
            #expect(ImageProviderFixture.captured.allSatisfy { $0.url?.host == "api.deepseek.com" })
            #expect(engine.imageGenerationStatus.contains("未调用图片接口"))
        } else {
            #expect(engine.sends.attempts == 0)
            #expect(!ImageProviderFixture.captured.contains { $0.url?.host == "api.cloudflare.com" })
            #expect(engine.usage.calls == 2)
            if mode == "hold" { #expect(engine.queuedCount == 0) }
        }
    }
}
