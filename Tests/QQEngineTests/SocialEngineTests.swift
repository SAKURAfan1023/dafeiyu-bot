import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import WeChatAIBot

private final class SocialModelFixture: URLProtocol {
    private static let captureLock = NSLock()
    nonisolated(unsafe) private static var captured: [String: Data] = [:]
    static func body(for path: String) throws -> String {
        captureLock.lock(); defer { captureLock.unlock() }
        return String(decoding: try #require(captured[path]), as: UTF8.self)
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "model.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.captureLock.lock(); Self.captured[request.url!.path] = body; Self.captureLock.unlock()
        let truncated = request.url!.path.hasPrefix("/truncated/")
        let response: [String: Any] = ["choices":[["finish_reason":truncated ? "length" : "stop", "message":["content":truncated ? "{\"decision\":" : "{\"decision\":\"draft\",\"content\":\"这个设计挺有意思，细节展开说说？\",\"parentID\":\"comment-a\",\"summary\":\"讨论独立游戏关卡的设计。\",\"reason\":\"有明确可接续的话题\"}"]]],"usage":["total_tokens":123]]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@MainActor private final class SocialSiteFixture: SocialAdapter {
    var uid = "synthetic-account"
    var writes = 0
    var dropResponse = false
    var holdIdentity = false
    var identityGate: CheckedContinuation<Void, Never>?
    var post = SocialPost(id: "synthetic-note", title: "游戏关卡", text: "这个游戏关卡使用了一种很有意思的谜题设计，欢迎讨论。", author: "测试作者", authorID: "synthetic-author", kind: "normal", imageCount: 0,
        comments: [SocialComment(id: "comment-a", authorID: "synthetic-member", author: "测试成员", text: "关卡之间的衔接可以怎么做？")], coverage: "合成文字夹具")
    func login() async throws -> String { "" }
    func identity() async throws -> SocialIdentity {
        if holdIdentity { await withCheckedContinuation { identityGate = $0 } }
        return SocialIdentity(id: uid, name: "合成测试账号")
    }
    func search(_ keyword: String) async throws -> [SocialCandidate] { [SocialCandidate(id: post.id, title: post.title, author: post.author, kind: post.kind)] }
    func read(_ id: String) async throws -> SocialPost { post }
    func submit(_ record: SocialRecord) async throws -> SocialWriteResult {
        writes += 1
        if dropResponse { throw AppFailure.message("合成提交后断线") }
        return SocialWriteResult(state: "accepted", externalID: "synthetic-reply", authorID: uid)
    }
    func verify(_ record: SocialRecord) async throws -> SocialWriteResult { SocialWriteResult(state: "confirmed", externalID: "synthetic-reply", authorID: uid) }
    func close() {}
    func cancelPending() {}
}

@Suite @MainActor struct SocialEngineTests {
    private func command(_ e: SocialEngine, _ action: String, record: SocialRecord? = nil, content: String? = nil) -> SocialCommand {
        SocialCommand(requestID: UUID(), action: action, revision: e.stored.revision, recordID: record?.id, hash: record?.hash, content: content)
    }
    private func prepare(_ dir: URL, site: SocialSiteFixture, modelPath: String = "") async throws -> SocialEngine {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SocialModelFixture.self]
        let engine = SocialEngine(directory: dir, adapter: site, session: URLSession(configuration: config))
        var settings = engine.stored.settings; settings.baseURL = "https://model.invalid" + modelPath; settings.model = "synthetic"
        var save = command(engine, "save"); save.settings = settings; try await engine.perform(save)
        var key = command(engine, "credentials"); key.key = "synthetic-model-key"; try await engine.perform(key)
        try await engine.perform(command(engine, "identity"))
        var bind = command(engine, "bind"); bind.expectedUID = site.uid; try await engine.perform(bind)
        try await engine.perform(command(engine, "search"))
        try await engine.perform(command(engine, "read", content: site.post.id))
        return engine
    }
    @Test func draftEditApproveAndReplayAreOneSubmission() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(), engine = try await prepare(dir, site: site)
        try await engine.perform(command(engine, "draft"))
        let old = try #require(engine.stored.records.last)
        #expect(old.state == .draft && site.writes == 0 && engine.stored.modelAttempts == 1)
        try await engine.perform(command(engine, "edit", record: old, content: "这个设计有点意思，后面怎么接？"))
        await #expect(throws: (any Error).self) { try await engine.perform(command(engine, "approve", record: old)) }
        let edited = try #require(engine.stored.records.last)
        let approve = command(engine, "approve", record: edited)
        try await engine.perform(approve); try await engine.perform(approve)
        #expect(site.writes == 1 && engine.attemptsToday == 1)
        #expect(engine.stored.records.last?.state == .confirmed)
        #expect(engine.stored.records.last?.reason.contains("公开可见性未知") == true)
        let disk = try String(contentsOf: dir.appendingPathComponent("social-state.json"))
        #expect(!disk.contains("synthetic-model-key"))
        let mode = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("social-state.json").path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }
    @Test func unknownDeliveryConsumesQuotaAndSurvivesRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(); site.dropResponse = true
        var engine: SocialEngine? = try await prepare(dir, site: site)
        try await engine!.perform(command(engine!, "draft"))
        let record = try #require(engine!.stored.records.last)
        await #expect(throws: (any Error).self) { try await engine!.perform(command(engine!, "approve", record: record)) }
        #expect(site.writes == 1 && engine!.blockingCount == 1 && engine!.attemptsToday == 1 && !engine!.running)
        engine = nil
        let reopened = SocialEngine(directory: dir, adapter: site)
        #expect(reopened.blockingCount == 1 && reopened.attemptsToday == 1)
        let unknown = try #require(reopened.stored.records.last)
        var ack = command(reopened, "acknowledgeUnknown", record: unknown); ack.acknowledge = true
        try await reopened.perform(ack)
        #expect(reopened.blockingCount == 0 && reopened.attemptsToday == 1 && site.writes == 1)
        #expect(reopened.stored.records.last?.state == .uncertain)
    }
    @Test func accountChangeContentChangeAndPausePreventWrites() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(), engine = try await prepare(dir, site: site)
        try await engine.perform(command(engine, "draft"))
        let record = try #require(engine.stored.records.last)
        site.post.text = "帖子内容已经改变"
        await #expect(throws: (any Error).self) { try await engine.perform(command(engine, "approve", record: record)) }
        #expect(site.writes == 0 && engine.attemptsToday == 0)
        site.post = record.post; site.uid = "another-synthetic-account"
        await #expect(throws: (any Error).self) { try await engine.perform(command(engine, "approve", record: record)) }
        #expect(!engine.running && site.writes == 0)
        site.uid = record.accountID
        await #expect(throws: (any Error).self) { try await engine.perform(command(engine, "approve", record: record)) }
        #expect(site.writes == 0)
    }
    @Test func twoInstancesCannotOwnSameState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = SocialEngine(directory: dir, adapter: SocialSiteFixture())
        let second = SocialEngine(directory: dir, adapter: SocialSiteFixture())
        #expect(first.error.isEmpty && !second.error.isEmpty)
    }
    @Test func personalityAndMemoryAreScopedAndGroundedInRealDeliveryState() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(); var state = SocialStored()
        state.memories = [SocialThreadMemory(accountID: "other-account", postID: site.post.id, summary: "其他账号私有标记"),
                          SocialThreadMemory(accountID: site.uid, postID: "other-note", summary: "其他帖子私有标记")]
        try JSONEncoder().encode(state).write(to: dir.appendingPathComponent("social-state.json"))
        let path = "/" + UUID().uuidString
        let e = try await prepare(dir, site: site, modelPath: path)
        var settings = e.stored.settings; settings.personality = .catgirl
        var save = command(e, "save"); save.settings = settings; try await e.perform(save)
        try await e.perform(command(e, "memoryNote", content: "原话是在自嘲，不是认真求助"))
        try await e.perform(command(e, "draft", content: "comment-a"))
        var request = try SocialModelFixture.body(for: path + "/chat/completions")
        #expect(request.contains("猫娘风格") && request.contains("原话是在自嘲"))
        #expect(!request.contains("其他账号私有标记") && !request.contains("其他帖子私有标记"))
        let first = try #require(e.stored.records.last)
        #expect(e.stored.memories?.first { $0.accountID == site.uid && $0.postID == site.post.id }?.summary == first.summary)
        e.pause()
        try await e.perform(command(e, "draft", content: "comment-a"))
        request = try SocialModelFixture.body(for: path + "/chat/completions")
        #expect(request.contains(first.summary) && !request.contains(first.text)) // Unsent drafts are not spoken history.
        let second = try #require(e.stored.records.last)
        try await e.perform(command(e, "approve", record: second))
        e.pause(); try await e.perform(command(e, "draft", content: "comment-a"))
        request = try SocialModelFixture.body(for: path + "/chat/completions")
        #expect(request.contains("confirmed") && request.contains(second.text) && site.writes == 1)
        e.pause(); try await e.perform(command(e, "forgetMemory"))
        #expect(e.stored.memories?.contains { $0.accountID == site.uid && $0.postID == site.post.id } == false)
        #expect(e.attemptsToday == 1) // Forgetting memory cannot reset send dedupe/quota.
        settings.memoryEnabled = false
        save = command(e, "save"); save.settings = settings; try await e.perform(save)
        try await e.perform(command(e, "draft", content: "comment-a"))
        request = try SocialModelFixture.body(for: path + "/chat/completions")
        #expect(!request.contains(second.text) && !request.contains("原话是在自嘲"))
        #expect(e.stored.memories?.contains { $0.accountID == site.uid && $0.postID == site.post.id } == false)
        let disk = try JSONDecoder().decode(SocialStored.self, from: Data(contentsOf: dir.appendingPathComponent("social-state.json")))
        #expect(disk.settings.personality == .catgirl && disk.settings.memoryEnabled == false)
    }
    @Test func oldSettingsMigrateWithoutLosingCustomPersonaAndMemoryIsBounded() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var state = SocialStored(); state.settings.persona = "旧的自定义表达"; state.boundUID = "synthetic-account"
        state.memories = (0..<205).map { SocialThreadMemory(accountID: state.boundUID, postID: "note-\($0)", summary: "合成摘要") }
        state.memories?.append(SocialThreadMemory(accountID: state.boundUID, postID: "expired-note", summary: "过期背景", updatedAt: Date().addingTimeInterval(-8 * 86400)))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any]); settings.removeValue(forKey: "personality"); settings.removeValue(forKey: "memoryEnabled"); json["settings"] = settings
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("social-state.json"))
        let e = SocialEngine(directory: dir, adapter: SocialSiteFixture())
        #expect(e.error.isEmpty && e.stored.settings.personality == nil && e.stored.settings.persona == "旧的自定义表达")
        #expect(e.stored.memories?.count == 200 && e.stored.memories?.contains { $0.postID == "expired-note" } == false)
        var invalid = SocialSettings(); invalid.personality = .custom
        #expect(throws: (any Error).self) { try invalid.validate() }
        invalid.persona = "自定义提示"; try invalid.validate()
    }
    @Test func truncatedModelOutputIsCountedAndStopsWithoutDraftOrWrite() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(), e = try await prepare(dir, site: site, modelPath: "/truncated/" + UUID().uuidString)
        await #expect(throws: (any Error).self) { try await e.perform(command(e, "draft")) }
        #expect(!e.running && e.stored.modelAttempts == 1 && e.stored.modelTokens == 123)
        #expect(e.stored.records.isEmpty && (e.stored.memories ?? []).isEmpty && site.writes == 0)
        #expect(e.error.contains("预算上限"))
    }
    @Test func pauseDuringIdentityCannotCreateNewRun() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(), e = try await prepare(dir, site: site)
        site.holdIdentity = true
        let start = command(e, "start")
        let pending = Task { try await e.perform(start) }
        while site.identityGate == nil { await Task.yield() }
        e.pause(); site.holdIdentity = false; site.identityGate?.resume(); site.identityGate = nil
        await #expect(throws: (any Error).self) { try await pending.value }
        #expect(!e.running && e.stored.modelAttempts == 0 && site.writes == 0)
    }
    @Test func reconcilingOldUnknownDoesNotInvalidateItsIndex() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(); var state = SocialStored(); state.boundUID = site.uid
        var old = SocialRecord(runID: UUID(), accountID: site.uid, post: site.post, text: "合成旧记录", summary: "", reason: "未知", fingerprint: "", hash: "old", revision: 1, state: .uncertain, externalID: "synthetic-reply")
        old.createdAt = Date().addingTimeInterval(-8 * 86400); old.reservedAt = old.createdAt; state.records = [old]
        try JSONEncoder().encode(state).write(to: dir.appendingPathComponent("social-state.json"))
        let e = SocialEngine(directory: dir, adapter: site)
        try await e.perform(command(e, "reconcile", record: old))
        #expect(e.blockingCount == 0 && e.stored.records.first?.state == .confirmed && site.writes == 0)
    }
    @Test func controlSurfaceRejectsUnauthenticatedAndForeignOrigin() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let e = SocialEngine(directory: dir, adapter: SocialSiteFixture())
        let server = try SocialControlServer(engine: e); server.start(); defer { server.stop() }
        let url = server.controlURL
        let (_, page) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(url.port!)/?section=records")!)
        #expect((page as? HTTPURLResponse)?.statusCode == 200)
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(url.port!)/api/status")!)
        let (_, denied) = try await URLSession.shared.data(for: req)
        #expect((denied as? HTTPURLResponse)?.statusCode == 403)
        req.setValue(url.fragment!, forHTTPHeaderField: "X-Social-Control")
        let (_, allowed) = try await URLSession.shared.data(for: req)
        #expect((allowed as? HTTPURLResponse)?.statusCode == 200)
        req.setValue("https://foreign.invalid", forHTTPHeaderField: "Origin")
        let (_, foreign) = try await URLSession.shared.data(for: req)
        #expect((foreign as? HTTPURLResponse)?.statusCode == 403)
        // Real browser UUIDs are lowercase; Swift's uuidString is uppercase.
        let requestID = UUID().uuidString.lowercased()
        var settings = e.stored.settings; settings.keyword = "合成 UI 保存"
        var action = URLRequest(url: URL(string: "http://127.0.0.1:\(url.port!)/api/action")!)
        action.httpMethod = "POST"; action.setValue(url.fragment!, forHTTPHeaderField: "X-Social-Control")
        action.setValue("http://127.0.0.1:\(url.port!)", forHTTPHeaderField: "Origin")
        action.setValue("application/json", forHTTPHeaderField: "Content-Type")
        action.httpBody = try JSONEncoder().encode(SocialCommand(requestID: UUID(uuidString: requestID)!, action: "save", revision: e.stored.revision, settings: settings))
        let (_, queued) = try await URLSession.shared.data(for: action)
        #expect((queued as? HTTPURLResponse)?.statusCode == 202)
        var job = URLRequest(url: URL(string: "http://127.0.0.1:\(url.port!)/api/job/\(requestID)")!)
        job.setValue(url.fragment!, forHTTPHeaderField: "X-Social-Control")
        var outcome = "pending"
        for _ in 0..<30 {
            let (data, _) = try await URLSession.shared.data(for: job)
            outcome = (try JSONSerialization.jsonObject(with: data) as? [String:String])?["state"] ?? "missing"
            if outcome != "pending" { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(outcome == "complete" && e.stored.settings.keyword == settings.keyword)
        #expect(!e.running && e.stored.modelAttempts == 0)
    }
}
