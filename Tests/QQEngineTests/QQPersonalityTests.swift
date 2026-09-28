import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot

private final class PersonalityModelProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var prompts: [String] = []
    static func reset() { lock.lock(); prompts = []; lock.unlock() }
    static var captured: [String] { lock.lock(); defer { lock.unlock() }; return prompts }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
        }
        let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let messages = object["messages"] as! [[String: Any]], prompt = messages[0]["content"] as! String
        Self.lock.lock(); Self.prompts.append(prompt); Self.lock.unlock()
        let style = QQPersonality.allCases.first { prompt.contains("当前会话唯一生效性格：" + $0.name) }
        #expect(style != nil)
        var answer: [String: Any] = ["text": "合成回复：" + (style?.name ?? "未识别"), "emotion": "neutral", "intensity": 0]
        if prompt.contains("[QQ_PARTICIPATION]") { answer["participate"] = true }
        let content = String(decoding: try! JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
        let result: [String: Any] = ["choices": [["message": ["content": content], "finish_reason": "stop"]]]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: result)); client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) @MainActor struct QQPersonalityEngineTests {
    @Test func panelPersistenceKeepsMemoryAndRollsBackStaleWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        seed.config.expectedSelfID = "12345"
        seed.config.targets = [QQTarget(number: "54321", name: "peer", group: false), QQTarget(number: "99999", name: "group", group: true)]
        seed.save()
        let file = directory.appendingPathComponent("qq-state.json")
        var raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var book = QQMemoryBook()
        book.append(QQMemoryEvent(id: "1", subject: "PEER", text: "synthetic preference blue", at: Date()))
        raw["memoryBooks"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(["12345:private:54321": book]))
        try JSONSerialization.data(withJSONObject: raw).write(to: file)
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        engine.setPersonaStyle("gentle", target: "private:54321")
        #expect(engine.error == nil); #expect(engine.memoryBooks["12345:private:54321"] == book)
        let restored = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(restored.config.persona(for: "private:54321").effectiveStyle == .gentle)
        #expect(restored.memoryBooks["12345:private:54321"] == book)
        engine.setPersonaStyle("invalid", target: "group:99999")
        #expect(engine.error != nil); #expect(engine.config.persona(for: "group:99999").effectiveStyle == .teasing)
        engine.setPersonaStyle("calm", target: "group:77777")
        #expect(engine.error != nil); #expect(engine.config.targets.count == 2)
        // A second legitimate panel changes the file; this stale panel must not override it.
        restored.setPersonaStyle("butler", target: "group:99999")
        engine.setPersonaStyle("calm", target: "private:54321")
        #expect(engine.error != nil); #expect(engine.config.persona(for: "private:54321").effectiveStyle == .gentle)
        let latest = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(latest.config.persona(for: "group:99999").effectiveStyle == .butler)
        #expect(latest.memoryBooks["12345:private:54321"] == book)
    }
    @Test(arguments: ["teasing", "gentle", "tsundere", "energetic", "calm", "butler", "catgirl", "tieba", "abstract", "drama", "proactive", "private", "owner", "reset", "invalid", "list", "quoted", "atOther", "foreign", "disabled", "paused", "duplicate", "unknown", "pauseQueue", "noParticipation", "order"])
    func commandIsolationAndReplyPipeline(_ mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("groupParticipation".utf8).write(to: directory.appendingPathComponent("message-shape"))
        if mode == "unknown" { try Data().write(to: directory.appendingPathComponent("drop-send")) }
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path, directory.path]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        PersonalityModelProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [PersonalityModelProtocol.self]
        let session = URLSession(configuration: cfg); defer { session.invalidateAndCancel() }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session))
        defer { engine.disconnect() }
        engine.config.endpoint = "ws://127.0.0.1:\(port)"; engine.config.expectedSelfID = "12345"
        engine.config.effectivePersona.stickersEnabled = false; engine.config.effectiveArtwork.enabled = false
        engine.config.effectiveImageGeneration.enabled = false; engine.config.effectiveOnlineEnabled = false
        engine.config.ai.cooldownSeconds = 1; engine.config.ai.effectiveSendLimits.globalIntervalSeconds = 1
        engine.config.effectiveMemoryEnabled = true
        engine.config.effectiveGroupParticipationEnabled = mode != "noParticipation"; engine.config.effectiveGroupParticipationEvery = mode == "proactive" ? 1 : 10
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect(); try #require(engine.connected, "\(engine.error ?? engine.status)")
        for contact in engine.contacts { engine.add(contact) }
        for index in engine.config.targets.indices { engine.config.targets[index].enabled = true }
        let key = mode == "private" ? "private:54321" : "group:99999"
        if mode == "reset" { engine.setPersonaStyle("gentle", target: key) }
        if mode == "disabled" { engine.config.targets[engine.config.targets.firstIndex { $0.key == key }!].enabled = false }
        let pipeline = QQPersonality(rawValue: mode) != nil || ["proactive", "order"].contains(mode)
        if pipeline { engine.config.effectiveMemoryEnabled = false }
        engine.start()
        if mode == "paused" { engine.pause() }
        let style = QQPersonality(rawValue: mode) ?? .gentle
        let command = mode == "reset" ? "/persona default" : mode == "invalid" ? "/persona nonexistent" : mode == "list" ? "/persona list" : "/persona " + style.rawValue
        func event(_ id: Int, _ text: String, group: String? = "99999", mention: Bool = false) -> [String: Any] {
            var parts: [[String: Any]] = [["type": "text", "data": ["text": text]]]
            if mention { parts.insert(["type": "at", "data": ["qq": "12345"]], at: 0) }
            var row: [String: Any] = ["post_type": "message", "self_id": 12345, "user_id": 54321, "sender": ["user_id": 54321], "message_id": id, "message_type": group == nil ? "private" : "group", "sub_type": group == nil ? "friend" : "normal", "message": parts]
            if let group { row["group_id"] = Int(group)! }
            return row
        }
        var first = event(1, command, group: mode == "private" ? nil : mode == "foreign" ? "77777" : "99999")
        if mode == "owner" { first["post_type"] = "message_sent"; first["user_id"] = 12345; first["sender"] = ["user_id": 12345] }
        if mode == "quoted" || mode == "atOther" {
            var parts = first["message"] as! [[String: Any]]
            parts.append(mode == "quoted" ? ["type": "reply", "data": ["id": "-12"]] : ["type": "at", "data": ["qq": "77777"]]); first["message"] = parts
        }
        var batch = [first]
        if pipeline { batch += [event(2, "今天聊天测试", mention: mode != "proactive"), event(3, "另一个群测试", group: "88888", mention: true)] }
        if mode == "order" { batch = [event(2, "先按原性格回复", mention: true), first, event(3, "切换后的回复", mention: true)] }
        if mode == "duplicate" { batch.append(first) }
        if mode == "pauseQueue" { batch.append(event(2, "/persona calm")) }
        try JSONSerialization.data(withJSONObject: batch).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
        let rejected = ["foreign", "disabled", "paused", "quoted", "atOther"].contains(mode)
        let until = Date().addingTimeInterval(rejected ? 0.5 : 9)
        while Date() < until {
            if engine.sends.confirmed >= (pipeline ? 3 : 1) || engine.sends.uncertain > 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if mode == "pauseQueue" { engine.pause(); try await Task.sleep(nanoseconds: 200_000_000) }
        if rejected {
            #expect(engine.sends.attempts == 0); #expect(engine.config.persona(for: key).effectiveStyle == .teasing)
        } else {
            #expect(engine.config.persona(for: key).effectiveStyle == (["reset", "invalid", "list"].contains(mode) ? .teasing : style))
            if mode == "unknown" { #expect(!engine.running); #expect(engine.sends.uncertain == 1) }
            else { #expect(engine.sends.confirmed == (pipeline ? 3 : 1)); #expect(engine.sends.uncertain == 0) }
        }
        #expect(engine.config.persona(for: "group:88888").effectiveStyle == .teasing)
        if mode != "private" { #expect(engine.config.persona(for: "private:54321").effectiveStyle == .teasing) }
        if pipeline {
            #expect(PersonalityModelProtocol.captured.count == 4)
            #expect(PersonalityModelProtocol.captured.prefix(2).allSatisfy { $0.contains("当前会话唯一生效性格：" + (mode == "order" ? QQPersonality.teasing.name : style.name)) })
            #expect(PersonalityModelProtocol.captured.suffix(2).allSatisfy { $0.contains("当前会话唯一生效性格：" + (mode == "order" ? style.name : QQPersonality.teasing.name)) })
            #expect(PersonalityModelProtocol.captured.contains { $0.contains("发送前的语义校对") })
        } else {
            #expect(engine.usage.calls == 0); #expect(PersonalityModelProtocol.captured.isEmpty)
            #expect(engine.memoryBooks.isEmpty); #expect(engine.groupMessageCounts.values.allSatisfy { $0 == 0 })
        }
        if !rejected && mode != "unknown" {
            let payload = try #require(String(data: Data(contentsOf: directory.appendingPathComponent("payloads")), encoding: .utf8))
            #expect(payload.contains("/persona"))
        }
        let expected = engine.config.persona(for: key).effectiveStyle
        engine.disconnect()
        let restored = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(restored.config.persona(for: key).effectiveStyle == expected)
        #expect(!restored.running)
    }
}
