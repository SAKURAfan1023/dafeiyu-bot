import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot

// A private URLSession intercepts every model request; no real API or credentials are used.
private final class DelayedModelProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var pending: [DelayedModelProtocol] = []
    private static var cancellations = 0
    private var stopped = false
    private var completed = false
    private var capturedBody = ""
    static var counts: (started: Int, cancelled: Int, bodies: [String]) {
        lock.lock(); defer { lock.unlock() }
        return (pending.count, cancellations, pending.map(\.capturedBody))
    }
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        pending = []; cancellations = 0
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }; body.append(contentsOf: bytes.prefix(count))
            }
        }
        capturedBody = String(decoding: body, as: UTF8.self)
        Self.pending.append(self)
    }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if !stopped { stopped = true; Self.cancellations += 1 }
    }
    static func completePending(intensity: Int = 3, summary: Bool = false, participate: Bool? = true) {
        lock.lock()
        let active = pending.filter { !$0.stopped && !$0.completed }
        active.forEach { $0.completed = true }
        lock.unlock()
        for item in active {
            let response = HTTPURLResponse(url: item.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            item.client?.urlProtocol(item, didReceive: response, cacheStoragePolicy: .notAllowed)
            if item.capturedBody.contains("[QQ_MEMORY_V2]") {
                let request = try! JSONSerialization.jsonObject(with: Data(item.capturedBody.utf8)) as! [String: Any]
                let messages = request["messages"] as! [[String: Any]]
                let input = try! JSONSerialization.jsonObject(with: Data((messages.last!["content"] as! String).utf8)) as! [String: Any]
                let source = (input["events"] as! [[String: Any]]).first!
                let delta: [String: Any] = ["summary": "当前会话中的合成资料", "changes": [["operation": "upsert", "replaces": [], "subject": source["subject"]!, "kind": "fact", "text": "当前会话的合成测试事实", "keywords": ["合成", "synthetic"], "importance": 2, "sourceID": source["id"]!, "evidence": String((source["text"] as! String).prefix(100)), "days": 90]]]
                let content = String(decoding: try! JSONSerialization.data(withJSONObject: delta), as: UTF8.self)
                let result: [String: Any] = ["choices": [["message": ["content": content], "finish_reason": "stop"]], "usage": ["total_tokens": 1]]
                item.client?.urlProtocol(item, didLoad: try! JSONSerialization.data(withJSONObject: result))
            } else if summary {
                item.client?.urlProtocol(item, didLoad: Data(#"{"choices":[{"message":{"content":"{\"summary\":\"用户喜欢蓝色，正在聊天。\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":1}}"#.utf8))
            } else {
                var answer: [String: Any] = ["text": "好耶，给本鱼加饭！", "emotion": "joy", "intensity": intensity]
                if item.capturedBody.contains("[QQ_PARTICIPATION]"), let participate { answer["participate"] = participate }
                if let request = try? JSONSerialization.jsonObject(with: Data(item.capturedBody.utf8)) as? [String: Any],
                   let messages = request["messages"] as? [[String: Any]], let prompt = messages.first?["content"] as? String,
                   let raw = prompt.components(separatedBy: "本轮可选表情 JSON：\n").dropFirst().first,
                   let options = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: String]] {
                    answer["sticker_id"] = options.first?["id"]
                }
                let content = String(decoding: try! JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
                let result: [String: Any] = ["choices": [["message": ["content": content], "finish_reason": "stop"]], "usage": ["total_tokens": 1]]
                item.client?.urlProtocol(item, didLoad: try! JSONSerialization.data(withJSONObject: result))
            }
            item.client?.urlProtocolDidFinishLoading(item)
        }
    }
}

@Suite(.serialized) @MainActor struct QQEngineTests {
    @Test(arguments: ["draftSilent", "reviewSilent", "invalidDecision", "ownerToOther", "direct"])
    func participationMayStaySilentWithoutSendingOrConsumingSendQuota(_ mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("groupParticipation".utf8).write(to: directory.appendingPathComponent("message-shape"))
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path, directory.path]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        DelayedModelProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [DelayedModelProtocol.self]
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel(); DelayedModelProtocol.reset() }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session))
        defer { engine.disconnect() }
        engine.config.endpoint = "ws://127.0.0.1:\(port)"; engine.config.expectedSelfID = "12345"
        engine.config.memoryEnabled = false; engine.config.effectiveGroupParticipationEnabled = true
        engine.config.effectiveGroupParticipationEvery = 2; engine.config.effectivePersona.stickersEnabled = true
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect(); try #require(engine.connected)
        engine.add(try #require(engine.contacts.first { $0.number == "99999" }))
        engine.config.targets[0].enabled = true; engine.start()
        var rows: [[String: Any]] = []
        for id in 1...2 {
            let owner = id == 2 && mode == "ownerToOther"
            var segments: [[String: Any]] = [["type": "text", "data": ["text": "合成成员在互相聊天"]]]
            if owner || mode == "direct" && id == 2 { segments.append(["type": "at", "data": ["qq": owner ? "54322" : "12345"]]) }
            rows.append(["post_type": owner ? "message_sent" : "message", "self_id": 12345, "user_id": owner ? 12345 : 54321,
                         "sender": ["user_id": owner ? 12345 : 54321], "message_type": "group", "sub_type": "normal", "group_id": 99999, "message_id": id, "message": segments])
        }
        try JSONSerialization.data(withJSONObject: rows).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            let started = DelayedModelProtocol.counts.started
            DelayedModelProtocol.completePending(participate: mode == "invalidDecision" ? nil : mode == "reviewSilent" ? started < 2 : false)
            if engine.logs.contains(where: { $0.detail.contains("保持安静") || $0.detail.contains("不代答") }) || engine.sends.confirmed > 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(engine.sends.confirmed == (mode == "direct" ? 1 : 0))
        #expect(engine.sends.attempts == engine.sends.confirmed)
        #expect(engine.usage.calls == (mode == "ownerToOther" ? 0 : ["reviewSilent", "direct"].contains(mode) ? 2 : 1))
        #expect(engine.running); #expect(engine.queuedCount == 0)
        #expect(engine.groupMessageCounts["group:99999"] == (mode == "direct" ? 1 : 0))
        if mode != "direct" { #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("payload").path)) }
    }

    @Test func groupTimelineIncludesBotAcrossMembersAndSkipsMediaOnlyParticipation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("groupParticipation".utf8).write(to: directory.appendingPathComponent("message-shape"))
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path, directory.path]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        DelayedModelProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [DelayedModelProtocol.self]
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel(); DelayedModelProtocol.reset() }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session))
        defer { engine.disconnect() }
        engine.config.endpoint = "ws://127.0.0.1:\(port)"; engine.config.expectedSelfID = "12345"
        engine.config.memoryEnabled = false; engine.config.effectiveVisionEnabled = false; engine.config.effectiveGroupParticipationEnabled = true
        engine.config.effectiveGroupParticipationEvery = 2
        engine.config.ai.cooldownSeconds = 1; engine.config.ai.effectiveSendLimits.globalIntervalSeconds = 1
        engine.config.effectivePersona.stickersEnabled = false
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect(); try #require(engine.connected)
        engine.add(try #require(engine.contacts.first { $0.number == "99999" }))
        engine.config.targets[0].enabled = true; engine.start()
        func event(_ id: Int, _ text: String?, mention: Bool = false) -> [String: Any] {
            var segments: [[String: Any]] = text.map { [["type": "text", "data": ["text": $0]]] } ?? [["type": "image", "data": ["file": "synthetic.png"]]]
            if mention { segments.insert(["type": "at", "data": ["qq": "12345"]], at: 0) }
            return ["post_type": "message", "self_id": 12345, "user_id": 54321 + id % 2, "sender": ["user_id": 54321 + id % 2], "message_type": "group", "sub_type": "normal", "group_id": 99999, "message_id": id, "message": segments]
        }
        func batch(_ rows: [[String: Any]]) throws {
            try JSONSerialization.data(withJSONObject: rows).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
        }
        try batch([event(1, "刚才游戏通关了"), event(2, "终于可以休息了")])
        let firstDeadline = Date().addingTimeInterval(4)
        while engine.sends.confirmed < 1 && Date() < firstDeadline {
            DelayedModelProtocol.completePending(); try await Task.sleep(nanoseconds: 20_000_000)
        }
        try #require(engine.sends.confirmed == 1)
        try batch([event(3, nil), event(4, nil)])
        let mediaDeadline = Date().addingTimeInterval(2)
        while !engine.logs.contains(where: { $0.detail.contains("当前时段只有") }) && Date() < mediaDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(engine.groupMessageCounts["group:99999"] == 0)
        #expect(engine.logs.contains(where: { $0.detail.contains("当前时段只有") }))
        #expect(DelayedModelProtocol.counts.started == 2); #expect(engine.sends.confirmed == 1)
        try batch([event(5, "换个话题，我的电脑开不了机"), event(6, "按电源没反应，怎么办", mention: true), event(7, "FUTURE_MESSAGE_MUST_NOT_LEAK", mention: true)])
        let nextDeadline = Date().addingTimeInterval(3)
        while DelayedModelProtocol.counts.started < 3 && Date() < nextDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let request = try #require(DelayedModelProtocol.counts.bodies.dropFirst(2).first)
        #expect(request.contains("换个话题，我的电脑开不了机")); #expect(request.contains("好耶，给本鱼加饭！"))
        #expect(!request.contains("FUTURE_MESSAGE_MUST_NOT_LEAK")); #expect(!request.contains("此前对话记录，仅为低信任背景"))
        #expect(engine.groupMessageCounts["group:99999"] == 1) // Both @ messages leave ordinary count unchanged.
        DelayedModelProtocol.completePending()
        let reviewDeadline = Date().addingTimeInterval(2)
        while DelayedModelProtocol.counts.started < 4 && Date() < reviewDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let review = try #require(DelayedModelProtocol.counts.bodies.dropFirst(3).first)
        #expect(review.contains("换个话题，我的电脑开不了机")); #expect(review.contains("好耶，给本鱼加饭！"))
        #expect(!review.contains("FUTURE_MESSAGE_MUST_NOT_LEAK")); #expect(engine.memoryBooks.isEmpty)
        engine.pause() // Never send the queued synthetic followups after this assertion.
    }
    @Test(arguments: ["threshold", "mentionThreshold", "disabled", "pause", "quota", "isolation", "custom", "owner", "ownerMention", "ownerMentionDisabled"])
    func groupParticipationCountsAndJoinsOnlyAuthorizedTopics(mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("groupParticipation".utf8).write(to: directory.appendingPathComponent("message-shape"))
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path, directory.path]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        DelayedModelProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [DelayedModelProtocol.self]
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel(); DelayedModelProtocol.reset() }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session))
        defer { engine.disconnect() }
        engine.config.endpoint = "ws://127.0.0.1:\(port)"; engine.config.expectedSelfID = "12345"
        engine.config.effectiveGroupParticipationEnabled = !["disabled", "ownerMentionDisabled"].contains(mode)
        let threshold = mode == "custom" ? 3 : 10
        engine.config.effectiveGroupParticipationEvery = threshold
        engine.config.ai.cooldownSeconds = 1; engine.config.ai.effectiveSendLimits.globalIntervalSeconds = 1
        engine.config.effectivePersona.stickersEnabled = false
        if mode == "quota" { engine.config.ai.dailyLimit = 1 }
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect(); try #require(engine.connected)
        for contact in engine.contacts where contact.group {
            engine.add(contact)
            if contact.number == "99999" || mode == "isolation" { engine.config.targets[engine.config.targets.count - 1].enabled = true }
        }
        engine.start(); try #require(engine.running)
        func event(_ id: Int, group: Int = 99999, mention: Bool = false) -> [String: Any] {
            var segments: [[String: Any]] = [["type": "text", "data": ["text": "TOPIC_\(group)_\(id)_END：大家讨论周末去海边散步"]]]
            if mention { segments.insert(["type": "at", "data": ["qq": "12345"]], at: 0) }
            return ["post_type": "message", "self_id": 12345, "user_id": 54321 + id % 2, "sender": ["user_id": 54321 + id % 2], "message_type": "group", "sub_type": "normal", "group_id": group, "message_id": id, "message": segments]
        }
        func batch(_ rows: [[String: Any]]) throws {
            try JSONSerialization.data(withJSONObject: rows).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
        }
        var first = (1..<threshold).map { event($0) }
        first.append(event(1)) // Duplicate event.
        var invalidSent = event(90); invalidSent["post_type"] = "message_sent"; first.append(invalidSent)
        if mode == "owner" {
            first[2]["user_id"] = 12345; first[2]["sender"] = ["user_id": 12345]; first[2]["post_type"] = "message_sent"
            first.append(first[2]) // Duplicate manual event must not increment again.
            try Data().write(to: directory.appendingPathComponent("self-echo"))
        }
        var old = event(91); old["time"] = Date().timeIntervalSince1970 - 300; first.append(old)
        var notice = event(92); notice["post_type"] = "notice"; first.append(notice)
        first.append(contentsOf: (1...4).map { event($0, group: 88888) })
        try batch(first)
        let admitted = Date().addingTimeInterval(3)
        while Date() < admitted {
            let primaryReady = ["disabled", "ownerMentionDisabled"].contains(mode) ? engine.rejectedScopedEvents >= 2 : engine.groupMessageCounts["group:99999"] == threshold - 1
            let otherReady = mode != "isolation" || engine.groupMessageCounts["group:88888"] == 4
            if primaryReady && otherReady { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(DelayedModelProtocol.counts.started == 0); #expect(engine.sends.attempts == 0)
        if mode == "disabled" { #expect(engine.groupMessageCounts.isEmpty); return }
        if mode != "ownerMentionDisabled" { try #require(engine.groupMessageCounts["group:99999"] == threshold - 1) }
        #expect(engine.groupMessageCounts["group:88888"] == (mode == "isolation" ? 4 : nil))
        var trigger = event(threshold, mention: ["mentionThreshold", "ownerMention", "ownerMentionDisabled"].contains(mode))
        if mode.hasPrefix("ownerMention") { trigger["user_id"] = 12345; trigger["sender"] = ["user_id": 12345]; trigger["post_type"] = "message_sent" }
        try batch([trigger])
        let triggered = Date().addingTimeInterval(3)
        while DelayedModelProtocol.counts.started == 0 && Date() < triggered { try await Task.sleep(nanoseconds: 20_000_000) }
        try #require(DelayedModelProtocol.counts.started == 1)
        #expect(engine.groupMessageCounts["group:99999"] == (mode == "ownerMentionDisabled" ? nil : ["mentionThreshold", "ownerMention"].contains(mode) ? threshold - 1 : 0))
        let draft = try #require(DelayedModelProtocol.counts.bodies.first)
        #expect(draft.contains("TOPIC_99999_1_END")) // Ordinary context is available to direct @ replies too.
        #expect(!draft.contains("TOPIC_88888")); #expect(!draft.contains("TOPIC_99999_90_END"))
        #expect(draft.contains("主动加入群话题") == (!["mentionThreshold", "ownerMention", "ownerMentionDisabled"].contains(mode)))
        if mode == "owner" || mode.hasPrefix("ownerMention") { #expect(draft.contains("[OWNER] 本账号主人")) }
        if ["mentionThreshold", "ownerMention"].contains(mode) {
            try batch([event(threshold + 1)])
            let queued = Date().addingTimeInterval(3)
            while engine.queuedCount == 0 && Date() < queued { try await Task.sleep(nanoseconds: 20_000_000) }
            #expect(engine.groupMessageCounts["group:99999"] == 0); #expect(engine.queuedCount == 1)
        }
        if mode == "pause" || mode == "threshold" {
            try batch((11...25).map { event($0) })
            let queued = Date().addingTimeInterval(3)
            while (engine.groupMessageCounts["group:99999"] != 5 || engine.queuedCount != 1) && Date() < queued { try await Task.sleep(nanoseconds: 20_000_000) }
            #expect(engine.groupMessageCounts["group:99999"] == 5); #expect(engine.queuedCount == 1)
        }
        if mode == "pause" {
            engine.pause(); #expect(engine.groupMessageCounts.isEmpty); #expect(engine.queuedCount == 0)
            DelayedModelProtocol.completePending(); try await Task.sleep(nanoseconds: 100_000_000)
            #expect(engine.sends.attempts == 0)
            engine.start(); #expect(engine.groupMessageCounts.isEmpty)
            return
        }
        let expected = ["threshold", "mentionThreshold", "ownerMention"].contains(mode) ? 2 : mode == "quota" ? 0 : 1
        let completed = Date().addingTimeInterval(4)
        repeat {
            DelayedModelProtocol.completePending()
            try await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < completed && (mode == "quota" ? !engine.logs.contains(where: { $0.state == .failed }) : engine.sends.confirmed < expected)
        #expect(engine.sends.confirmed == expected); #expect(engine.sends.attempts == expected)
        #expect(engine.usage.calls == (mode == "quota" ? 1 : expected * 2))
        if mode == "threshold" {
            let secondDraft = try #require(DelayedModelProtocol.counts.bodies.dropFirst(2).first)
            #expect(secondDraft.contains("TOPIC_99999_11_END")); #expect(secondDraft.contains("TOPIC_99999_20_END"))
            #expect(!secondDraft.contains("TOPIC_99999_25_END")); #expect(secondDraft.contains("TOPIC_99999_1_END"))
        }
        if mode == "owner" {
            try await Task.sleep(nanoseconds: 100_000_000)
            #expect(engine.groupMessageCounts["group:99999"] == 1) // Concurrent human input counts; bot echoes before/after ack do not.
        }
        if expected > 0 {
            let payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("payload"))) as? [String: Any])
            #expect(payload["group_id"] as? String == "99999")
        }
        #expect(engine.memoryBooks.isEmpty) // Group fragments never enter a member's personal memory.
        let disk = try String(contentsOf: directory.appendingPathComponent("qq-state.json"), encoding: .utf8)
        #expect(!disk.contains("TOPIC_"))
    }
    @Test(arguments: ["capture", "pause", "clear", "timed"])
    func structuredMemoryLearnsWithoutSendingAndSurvivesPause(mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("groupParticipation".utf8).write(to: directory.appendingPathComponent("message-shape"))
        if mode == "timed" {
            let seed = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
            seed.config.expectedSelfID = "12345"; seed.save()
            let file = directory.appendingPathComponent("qq-state.json")
            var stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var book = QQMemoryBook()
            book.append(QQMemoryEvent(id: "-10", subject: "OWNER", text: "合成的昨日约定", at: Date().addingTimeInterval(-601)))
            stored["memoryBooks"] = ["12345:group:99999": try JSONSerialization.jsonObject(with: JSONEncoder().encode(book))]
            try JSONSerialization.data(withJSONObject: stored).write(to: file)
        }
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path, directory.path]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        DelayedModelProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [DelayedModelProtocol.self]
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel(); DelayedModelProtocol.reset() }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session))
        defer { engine.disconnect() }
        engine.config.endpoint = "ws://127.0.0.1:\(port)"; engine.config.expectedSelfID = "12345"
        engine.config.memoryEnabled = true; engine.config.effectiveMemoryOptions.messageThreshold = 4
        engine.config.effectiveGroupParticipationEnabled = false
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect(); try #require(engine.connected)
        engine.add(try #require(engine.contacts.first { $0.number == "99999" && $0.group }))
        engine.config.targets[0].enabled = true; engine.start(); try #require(engine.running)
        if mode != "timed" {
            let events: [[String: Any]] = (1...4).map { id in
                let sender = id == 2 ? 12345 : 54321
                return ["post_type": id == 2 ? "message_sent" : "message", "self_id": 12345, "user_id": sender, "sender": ["user_id": sender], "message_type": "group", "sub_type": "normal", "group_id": 99999, "message_id": id, "message": [["type": "text", "data": ["text": "合成测试资料 \(id)"]]]]
            }
            try JSONSerialization.data(withJSONObject: events).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
        }
        let deadline = Date().addingTimeInterval(4)
        while DelayedModelProtocol.counts.started == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try #require(DelayedModelProtocol.counts.started == 1)
        #expect(DelayedModelProtocol.counts.bodies.first?.contains("QQ_MEMORY_V2") == true)
        #expect(DelayedModelProtocol.counts.bodies.first?.contains("OWNER") == true)
        if mode == "pause" { engine.pause() }
        if mode == "clear" { engine.clearMemory(engine.config.targets[0].id) }
        DelayedModelProtocol.completePending()
        let completed = Date().addingTimeInterval(3)
        while ["capture", "timed"].contains(mode), engine.memoryBooks["12345:group:99999"]?.pending.isEmpty != true, Date() < completed { try await Task.sleep(nanoseconds: 20_000_000) }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(engine.sends.attempts == 0); #expect(engine.groupMessageCounts.isEmpty); #expect(engine.usage.calls == 1)
        engine.disconnect()
        let reloaded = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        if mode == "pause" { #expect(reloaded.memoryBooks["12345:group:99999"]?.pending.count == 4) }
        else if mode == "clear" { #expect(reloaded.memoryBooks.isEmpty) }
        else { #expect(reloaded.memoryBooks["12345:group:99999"]?.items.count == 2); #expect(reloaded.memoryBooks["12345:group:99999"]?.pending.isEmpty == true) }
    }
    @Test func learningPayloadIsCompleteAndCandidateAuthorityMatchesSuppliedBudget() async throws {
        DelayedModelProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [DelayedModelProtocol.self]
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel(); DelayedModelProtocol.reset() }
        var book = QQMemoryBook()
        for i in 0..<32 { book.append(QQMemoryEvent(id: "\(i)", subject: "PEER", text: String(repeating: "\"", count: 1200), at: Date())) }
        for _ in 0..<48 { book.importLegacy(text: String(repeating: "旧记忆", count: 200), subject: "PEER", at: Date()) }
        let batch = book.batch(), candidates = book.items
        #expect(batch.count < 32)
        let task = Task { try await DeepSeekClient(session: session).learnQQMemory(key: "synthetic", config: QQConfig().ai, events: batch, candidates: candidates, reserve: {}) }
        let until = Date().addingTimeInterval(3)
        while DelayedModelProtocol.counts.started == 0 && Date() < until { try await Task.sleep(nanoseconds: 20_000_000) }
        let raw = try #require(DelayedModelProtocol.counts.bodies.first)
        let request = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        let messages = try #require(request["messages"] as? [[String: Any]])
        let payload = try #require(messages.last?["content"] as? String)
        #expect(payload.count <= 11500)
        let fields = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        #expect((fields["events"] as? [Any])?.count == batch.count)
        let supplied = try #require(fields["existing"] as? [[String: Any]])
        #expect(supplied.count < candidates.count)
        DelayedModelProtocol.completePending()
        let (_, _, ids) = try await task.value
        #expect(ids == Set(supplied.compactMap { $0["id"] as? String }))
    }
    @Test func removingTargetPersistsWithoutStarting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        engine.config.expectedSelfID = "12345"
        engine.add(QQContact(number: "54321", name: "fixture", group: false))
        let target = try #require(engine.config.targets.first)
        engine.remove(target.id)
        try #require(engine.error == nil)
        let reloaded = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(reloaded.config.targets.isEmpty)
        #expect(reloaded.sends.attempts == 0)
    }
    @Test func stalePanelCannotOverwriteNewerConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        owner.config.expectedSelfID = "12345"; owner.save()
        try #require(owner.error == nil)
        let stale = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        owner.config.ai.prompt = "newer configuration"; owner.save()
        try #require(owner.error == nil)
        let file = directory.appendingPathComponent("qq-state.json"), before = try Data(contentsOf: directory.appendingPathComponent("qq-state.json"))
        stale.save()
        #expect(stale.error != nil)
        #expect(try Data(contentsOf: file) == before)
    }
    @Test(arguments: ["pause", "pauseReview", "takeOver", "disconnect", "complete", "deadline", "noSticker", "missingSticker", "unknown", "cooldown", "fastStickers", "longRunQueue", "groupMentionOnly", "groupQuotedReply", "periodicStickers", "memory", "memoryIsolation", "privateQuotedReply", "privateQuotedOwn", "privateQuotedWrongPeer", "privateQuotedMissing", "privateTimeline", "privateOwnerIntervenes"])
    func cancelsGenerationAndDropsQueuedMessages(control: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = control.hasPrefix("group")
        if group || control.hasPrefix("private") { try Data(control.utf8).write(to: directory.appendingPathComponent("message-shape")) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py")
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [fixture.path, directory.path]
        server.standardOutput = output
        try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let port = try #require(Int(line))

        DelayedModelProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedModelProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); DelayedModelProtocol.reset() }
        if control == "memoryIsolation" {
            let seed = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
            seed.config.expectedSelfID = "12345"; seed.save()
            let file = directory.appendingPathComponent("qq-state.json")
            var state = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var memories: [String: Any] = [:]
            for (key, marker) in [("12345:private:54321:54321", "OWNER_MEMORY"), ("12345:private:98765:98765", "OTHER_FRIEND"), ("12345:group:54321:54321", "OTHER_GROUP"), ("99999:private:54321:54321", "OTHER_ACCOUNT")] {
                let summary = try QQMemorySummary.decode("{\"summary\":\"" + marker + "\"}")
                memories[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary))
            }
            state.removeValue(forKey: "memoryBooks") // Genuine legacy fixture predates the new field.
            state["memories"] = memories
            try JSONSerialization.data(withJSONObject: state).write(to: file)
        }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory,
                              modelClient: DeepSeekClient(session: session), stickerLibrary: QQStickerLibrary(directory: control == "missingSticker" ? nil : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/QQStickers")))
        defer { engine.disconnect() }
        engine.config.endpoint = "ws://127.0.0.1:\(port)"
        engine.config.expectedSelfID = "12345"
        if ["cooldown", "fastStickers", "periodicStickers", "memory"].contains(control) || control.hasPrefix("privateQuoted") { engine.config.ai.cooldownSeconds = 1; engine.config.ai.effectiveSendLimits.globalIntervalSeconds = 1 }
        if ["fastStickers", "periodicStickers"].contains(control) { engine.config.effectivePersona.stickerIntervalSeconds = 1 }
        if ["memory", "memoryIsolation"].contains(control) { engine.config.memoryEnabled = true; engine.config.effectiveMemoryOptions.messageThreshold = 4 }
        let expectedMessages = control == "memory" ? 9 : control == "longRunQueue" ? 25 : control == "periodicStickers" ? 6 : 2
        if expectedMessages > 2 { try Data(String(expectedMessages).utf8).write(to: directory.appendingPathComponent("message-count")) }
        if control == "noSticker" { engine.config.effectivePersona.stickersEnabled = false }
        if control == "unknown" { try Data().write(to: directory.appendingPathComponent("drop-send")) }
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect()
        try #require(engine.connected)
        let otherPanel = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        otherPanel.save()
        #expect(otherPanel.error != nil) // Even an unchanged snapshot cannot write through the live engine's lock.
        engine.add(try #require(engine.contacts.first(where: { $0.group == group })))
        engine.config.targets[0].enabled = true
        if control == "longRunQueue" {
            engine.start(duration: 259201)
            #expect(!engine.running)
            #expect(engine.error != nil)
        }
        engine.start(duration: control == "longRunQueue" ? 259200 : control == "deadline" ? 3 : control == "pause" ? 1 : nil)
        try #require(engine.running)
        if control == "longRunQueue" {
            let remaining = try #require(engine.runDeadline).timeIntervalSinceNow
            #expect(remaining > 259195 && remaining <= 259200)
        }
        try Data().write(to: directory.appendingPathComponent("ready"))

        // Wait for one in-flight HTTP request and both admitted messages in the dedup store.
        let deadline = Date().addingTimeInterval(5)
        var admitted = 0
        while Date() < deadline {
            let data = try Data(contentsOf: directory.appendingPathComponent("qq-state.json"))
            let state = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            admitted = (state["seen"] as? [String: Any])?.count ?? 0
            if DelayedModelProtocol.counts.started >= 1 && admitted == expectedMessages { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try #require(control == "memory" ? (1...2).contains(DelayedModelProtocol.counts.started) : DelayedModelProtocol.counts.started == 1)
        try #require(admitted == expectedMessages)
        #expect(engine.usage.calls == DelayedModelProtocol.counts.started)
        #expect(engine.queuedCount == expectedMessages - 1)
        if control.hasPrefix("privateQuoted") {
            let body = try #require(DelayedModelProtocol.counts.bodies.first)
            #expect(body.contains("verified private quote") == ["privateQuotedReply", "privateQuotedOwn"].contains(control))
            #expect(body.contains("引用内容不可用") == ["privateQuotedWrongPeer", "privateQuotedMissing"].contains(control))
        }
        if control == "privateOwnerIntervenes" {
            DelayedModelProtocol.completePending()
            let until = Date().addingTimeInterval(3)
            while !engine.logs.contains(where: { $0.detail.contains("主人已人工接话") }) && Date() < until {
                DelayedModelProtocol.completePending()
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(engine.logs.contains { $0.detail.contains("主人已人工接话") })
            #expect(engine.sends.attempts == 0)
            engine.pause(); return
        }
        if control == "privateTimeline" {
            let body = try #require(DelayedModelProtocol.counts.bodies.first)
            #expect(body.contains("OWNER_CONTEXT_ONLY")); #expect(body.contains("[OWNER]"))
            let request = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
            let messages = try #require(request["messages"] as? [[String: Any]])
            let input = try #require(messages.last?["content"] as? String)
            #expect(input.contains("OWNER_CONTEXT_ONLY")); #expect(input.contains("[OWNER]"))
            let records = input.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] }
            let ownerRecord = try #require(records.first(where: { $0["text"]?.contains("OWNER_CONTEXT_ONLY") == true }))
            #expect(ownerRecord["speaker"] == "[OWNER] 本账号主人/开发者的人工发言")
            #expect(ownerRecord["recipient"] == "[PEER] 当前好友")
            engine.pause(); #expect(engine.sends.attempts == 0); return
        }
        if control == "memoryIsolation" {
            let body = try #require(DelayedModelProtocol.counts.bodies.first)
            #expect(body.contains("OWNER_MEMORY"))
            for forbidden in ["OTHER_FRIEND", "OTHER_GROUP", "OTHER_ACCOUNT"] { #expect(!body.contains(forbidden)) }
            engine.pause()
            #expect(engine.sends.attempts == 0)
            return
        }
        if control == "memory" {
            let until = Date().addingTimeInterval(12)
            while (engine.sends.confirmed < 9 || engine.memoryBusy || engine.memoryBooks["12345:private:54321"]?.items.isEmpty != false) && Date() < until {
                DelayedModelProtocol.completePending()
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(engine.sends.confirmed == 9)
            #expect(engine.usage.calls == 18 + DelayedModelProtocol.counts.bodies.filter { $0.contains("[QQ_MEMORY_V2]") }.count)
            #expect(Set(engine.memoryBooks.keys) == ["12345:private:54321"])
            engine.disconnect()
            let reloaded = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
            #expect(reloaded.memoryBooks.values.first?.items.contains { $0.text == "当前会话的合成测试事实" } == true)
            reloaded.clearMemory(try #require(reloaded.config.targets.first).id)
            #expect(reloaded.memoryBooks.isEmpty)
            let cleared = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
            #expect(cleared.memoryBooks.isEmpty)
            return
        }
        if ["complete", "noSticker", "missingSticker", "unknown", "cooldown", "fastStickers", "groupMentionOnly", "groupQuotedReply", "periodicStickers"].contains(control) || control.hasPrefix("privateQuoted") {
            // Positive control: this same fixture must detect a send when generation completes.
            DelayedModelProtocol.completePending(intensity: control == "periodicStickers" ? 1 : 3)
            let desired = control == "periodicStickers" ? 6 : (["cooldown", "fastStickers"].contains(control) || control.hasPrefix("privateQuoted")) ? 2 : 1
            let sendDeadline = Date().addingTimeInterval(control == "periodicStickers" ? 10 : 4)
            while engine.sends.confirmed < desired && engine.sends.uncertain == 0 && Date() < sendDeadline {
                DelayedModelProtocol.completePending(intensity: control == "periodicStickers" ? 1 : 3)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            engine.pause()
            #expect(engine.sends.attempts == desired)
            #expect(engine.sends.confirmed == (control == "unknown" ? 0 : desired))
            #expect(engine.sends.uncertain == (control == "unknown" ? 1 : 0))
            let actions = try String(contentsOf: directory.appendingPathComponent("actions"), encoding: .utf8)
            let expectedAction = group ? "send_group_msg" : "send_private_msg"
            #expect(actions.contains(expectedAction))
            let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("payload"))) as? [String: Any]
            if group { #expect(payload?["group_id"] as? String == "99999") }
            let segments = try #require(payload?["message"] as? [[String: Any]])
            if (["noSticker", "missingSticker", "cooldown"].contains(control) || control.hasPrefix("privateQuoted")) { #expect(segments.count == 1) }
            else {
                try #require(segments.count == 2)
                #expect(segments[1]["type"] as? String == "image")
                #expect(((segments[1]["data"] as? [String: String])?["file"] ?? "").hasPrefix("base64://"))
            }
            #expect(actions.components(separatedBy: expectedAction).count - 1 == desired)
            if control == "periodicStickers" {
                let lines = try String(contentsOf: directory.appendingPathComponent("payloads"), encoding: .utf8).split(separator: "\n")
                let counts = try lines.map { line -> Int in
                    let payload = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                    return (payload["message"] as! [[String: Any]]).count
                }
                #expect(counts == [1, 1, 2, 1, 1, 2])
            }
            if ["privateQuotedReply", "privateQuotedOwn"].contains(control) {
                let second = try #require(DelayedModelProtocol.counts.bodies.last)
                #expect(second.contains("verified private quote")) // Resolved quotes survive alongside the refreshed timeline.
                #expect(actions.components(separatedBy: "get_friend_msg_history").count - 1 == 5)
                #expect(!actions.contains("get_msg"))
            }
            if control != "unknown" {
                let stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("qq-state.json"))) as? [String: Any])
                let ids = try #require(stored["botMessageIDs"] as? [String: Double])
                #expect(ids["12345:" + (group ? "group:99999" : "private:54321") + ":99"] != nil)
            }
            let encoded = try Data(contentsOf: directory.appendingPathComponent("qq-state.json"))
            let state = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            let histories = try #require(state["stickerHistory"] as? [String: Any])
            if segments.contains(where: { $0["type"] as? String == "image" }) {
                let entries = try #require(histories["12345:" + (group ? "group:99999" : "private:54321")] as? [[String: Any]])
                let hashes = entries.compactMap { $0["sha256"] as? String }
                #expect(Set(hashes).count == hashes.count)
                #expect(!hashes.isEmpty)
                engine.disconnect()
                let restored = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
                restored.save()
                let restoredState = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("qq-state.json"))) as? [String: Any])
                #expect(NSDictionary(dictionary: histories).isEqual(to: restoredState["stickerHistory"] as! [String: Any]))
            }
            #expect(engine.preview == "好耶，给本鱼加饭！")
            return
        }
        if control == "pauseReview" {
            DelayedModelProtocol.completePending()
            let until = Date().addingTimeInterval(2)
            while DelayedModelProtocol.counts.started < 2 && Date() < until { try await Task.sleep(nanoseconds: 20_000_000) }
            try #require(DelayedModelProtocol.counts.started == 2)
        }
        switch control {
        case "pause", "pauseReview", "longRunQueue": engine.pause()
        case "takeOver": engine.takeOver(engine.config.targets[0].id)
        case "deadline":
            let timeout = Date().addingTimeInterval(5)
            while engine.running && Date() < timeout { try await Task.sleep(nanoseconds: 20_000_000) }
            #expect(engine.runDeadline == nil)
        default: engine.disconnect()
        }
        #expect(!engine.running)
        #expect(engine.queuedCount == 0)
        if control == "takeOver" { #expect(!engine.config.targets[0].enabled) }

        let cancellationDeadline = Date().addingTimeInterval(2)
        while DelayedModelProtocol.counts.cancelled == 0 && Date() < cancellationDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(DelayedModelProtocol.counts.cancelled == 1)
        DelayedModelProtocol.completePending()
        if engine.connected {
            engine.config.targets[0].enabled = true
            engine.start() // Resume must not replay the previously queued second message.
            #expect(engine.running)
        }
        try await Task.sleep(nanoseconds: control == "pause" ? 1_200_000_000 : 300_000_000)
        if engine.connected { #expect(engine.running) } // An old deadline cannot stop the resumed run.
        engine.pause()
        #expect(DelayedModelProtocol.counts.started == (control == "pauseReview" ? 2 : 1))
        #expect(engine.usage.calls == (control == "pauseReview" ? 2 : 1))
        #expect(engine.sends.attempts == 0)
        #expect(engine.sends.confirmed == 0)
        let actions = try String(contentsOf: directory.appendingPathComponent("actions"), encoding: .utf8)
        #expect(!actions.contains("send_private_msg"))
        #expect(!actions.contains("send_group_msg"))
    }
}
