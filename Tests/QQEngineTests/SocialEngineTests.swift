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
    var reads = 0
    var identityCalls = 0
    var restricted = false
    var receiptWarning = false
    var duringSubmit: (() async -> Void)?
    var identityGate: CheckedContinuation<Void, Never>?
    var post = SocialPost(id: "synthetic-note", title: "游戏关卡", text: "这个游戏关卡使用了一种很有意思的谜题设计，欢迎讨论。", author: "测试作者", authorID: "synthetic-author", kind: "normal", imageCount: 0,
        comments: [SocialComment(id: "comment-a", authorID: "synthetic-member", author: "测试成员", text: "关卡之间的衔接可以怎么做？")], coverage: "合成文字夹具")
    func login() async throws -> String { "" }
    func identity() async throws -> SocialIdentity {
        identityCalls += 1
        if holdIdentity { await withCheckedContinuation { identityGate = $0 } }
        return SocialIdentity(id: uid, name: "合成测试账号")
    }
    func search(_ keyword: String) async throws -> [SocialCandidate] {
        if restricted { throw SocialAccessFailure.restricted }
        return [SocialCandidate(id: post.id, title: post.title, author: post.author, kind: post.kind)] }
    func read(_ id: String) async throws -> SocialPost { reads += 1; return post }
    func submit(_ record: SocialRecord) async throws -> SocialWriteResult {
        writes += 1
        await duringSubmit?()
        if dropResponse { throw AppFailure.message("合成提交后断线") }
        return SocialWriteResult(state: "accepted", externalID: "synthetic-reply", authorID: uid, restricted: receiptWarning)
    }
    func verify(_ record: SocialRecord) async throws -> SocialWriteResult { SocialWriteResult(state: "confirmed", externalID: "synthetic-reply", authorID: uid) }
    func close() {}
    func cancelPending() {}
}

@Suite @MainActor struct SocialEngineTests {
    private func command(_ e: SocialEngine, _ action: String, record: SocialRecord? = nil, content: String? = nil) -> SocialCommand {
        SocialCommand(requestID: UUID(), action: action, revision: e.stored.revision, recordID: record?.id, hash: record?.hash, content: content)
    }
    private func prepare(_ dir: URL, site: SocialSiteFixture, modelPath: String = "", platform: SocialPlatform = .xiaohongshu) async throws -> SocialEngine {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SocialModelFixture.self]
        var clock = Date()
        let engine = SocialEngine(platform: platform, directory: dir, adapter: site, session: URLSession(configuration: config), readClock: { clock = clock.addingTimeInterval(3601); return clock })
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
    @Test func browseAndReviewHaveDistinctModelParticipationContracts() async throws {
        for mode in [SocialMode.browse, .review, .auto] {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = "/mode-" + UUID().uuidString
            let site = SocialSiteFixture(), engine = try await prepare(dir, site: site, modelPath: path)
            var settings = engine.stored.settings; settings.mode = mode
            var save = command(engine, "save"); save.settings = settings; try await engine.perform(save)
            try await engine.perform(command(engine, "draft"))
            let body = try SocialModelFixture.body(for: path + "/chat/completions")
            let object = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
            let messages = try #require(object["messages"] as? [[String: String]])
            let system = try #require(messages.first?["content"])
            #expect(system.contains("decision 必须为 skip") == (mode == .browse))
            #expect(system.contains("允许生成待审核草稿（decision=draft）") == (mode != .browse))
            #expect(engine.stored.records.last?.state == (mode == .browse ? .skipped : .draft))
            #expect(site.writes == 0)
            engine.shutdown()
        }
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
        try Data("synthetic warning upgrade".utf8).write(to: dir.appendingPathComponent(".platform-warning"))
        let e = SocialEngine(directory: dir, adapter: SocialSiteFixture())
        #expect(e.error.isEmpty && e.stored.settings.personality == nil && e.stored.settings.persona == "旧的自定义表达")
        #expect(e.stored.warningAt != nil)
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

    @Test func warningBlocksReadsAndModelUntilExplicitlyClearedAndSurvivesRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture()
        var e: SocialEngine? = try await prepare(dir, site: site)
        try await e!.perform(command(e!, "draft"))
        try await e!.perform(command(e!, "reportWarning"))
        let calls = site.identityCalls, reads = site.reads, models = e!.stored.modelAttempts
        for action in ["login", "identity", "search", "read", "draft", "start", "rebase", "reconcile"] {
            await #expect(throws: (any Error).self) { try await e!.perform(command(e!, action, content: site.post.id)) }
        }
        // Local background corrections remain available without querying the platform.
        try await e!.perform(command(e!, "memoryNote", content: "合成本地背景"))
        #expect(site.identityCalls == calls && site.reads == reads && e!.stored.modelAttempts == models)
        #expect(e!.stored.warningAt != nil && !e!.running && site.writes == 0)
        e = nil
        let reopened = SocialEngine(directory: dir, adapter: site)
        #expect(reopened.stored.warningAt != nil)
        await #expect(throws: (any Error).self) { try await reopened.perform(command(reopened, "acknowledgeWarning")) }
        var ack = command(reopened, "acknowledgeWarning"); ack.acknowledge = true
        try await reopened.perform(ack)
        #expect(reopened.stored.warningAt == nil && !reopened.running && reopened.stored.modelAttempts == models)
    }

    @Test func readCooldownPersistsAndAdapterRestrictionsLatch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(); var now = Date()
        var e: SocialEngine? = SocialEngine(directory: dir, adapter: site, readClock: { now })
        try await e!.perform(command(e!, "identity"))
        var bind = command(e!, "bind"); bind.expectedUID = site.uid; try await e!.perform(bind)
        try await e!.perform(command(e!, "search"))
        await #expect(throws: (any Error).self) { try await e!.perform(command(e!, "read", content: site.post.id)) }
        #expect(site.reads == 0 && e!.stored.warningAt == nil)
        let deadline = e!.stored.nextReadAt
        e = nil
        let restored = SocialEngine(directory: dir, adapter: site, readClock: { now })
        #expect(restored.stored.nextReadAt == deadline)
        await #expect(throws: (any Error).self) { try await restored.perform(command(restored, "search")) }
        now = now.addingTimeInterval(Double(restored.stored.settings.readIntervalSeconds ?? 30) + 1); site.restricted = true
        await #expect(throws: (any Error).self) { try await restored.perform(command(restored, "search")) }
        #expect(restored.stored.warningAt != nil && !restored.running)
    }

    @Test func warningDuringSubmitPreservesReceiptAndNeverStartsReadback() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(), e = try await prepare(dir, site: site)
        try await e.perform(command(e, "draft"))
        let draft = try #require(e.stored.records.last)
        site.duringSubmit = { try? await e.perform(self.command(e, "reportWarning")) }
        try await e.perform(command(e, "approve", record: draft))
        #expect(e.stored.records.last?.state == .accepted && e.attemptsToday == 1 && !e.running && e.stored.warningAt != nil)
    }

    @Test func platformAndTemporaryCredentialsAreScopedAndBilibiliSupportsWrite() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let access = SocialModelAccess(), site = SocialSiteFixture()
        site.post.platform = .bilibili
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SocialModelFixture.self]
        var clock = Date()
        let e = SocialEngine(platform: .bilibili, directory: dir, adapter: site, session: URLSession(configuration: config), modelAccess: access, readClock: { clock = clock.addingTimeInterval(3601); return clock })
        var settings = e.stored.settings; settings.baseURL = "https://model.invalid/bilibili"; settings.model = "synthetic"
        var save = command(e, "save"); save.settings = settings; try await e.perform(save)
        var key = command(e, "credentials"); key.key = "synthetic-shared-key"; try await e.perform(key)
        #expect(access.temporary[settings.baseURL] == "synthetic-shared-key" && access.temporary["https://another.invalid"] == nil)
        try await e.perform(command(e, "identity")); var bind = command(e, "bind"); bind.expectedUID = site.uid; try await e.perform(bind)
        try await e.perform(command(e, "search")); try await e.perform(command(e, "read", content: site.post.id)); try await e.perform(command(e, "draft"))
        let draft = try #require(e.stored.records.last)
        try await e.perform(command(e, "approve", record: draft))
        #expect(site.writes == 1 && e.attemptsToday == 1 && e.stored.records.last?.state == .confirmed && draft.post.platform == .bilibili)
        var mismatch = command(e, "pause"); mismatch.platform = .xiaohongshu
        await #expect(throws: (any Error).self) { try await e.perform(mismatch) }
        #expect(draft.post.url.host == "www.bilibili.com")
    }

    @Test func platformRoutingAndJobReplayCannotCrossEngines() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let xhs = SocialEngine(directory: dir, adapter: SocialSiteFixture())
        let bili = SocialEngine(platform: .bilibili, directory: dir.appendingPathComponent("bilibili"), adapter: SocialSiteFixture())
        let server = try SocialControlServer(engines: [.xiaohongshu:xhs,.bilibili:bili]); server.start(); defer { server.stop() }
        let base = "http://127.0.0.1:\(server.controlURL.port!)"
        func request(_ path: String, command: SocialCommand? = nil) async throws -> (Data, Int) {
            var r = URLRequest(url: URL(string: base + path)!)
            r.setValue(server.controlURL.fragment!, forHTTPHeaderField: "X-Social-Control")
            if let command {
                r.httpMethod = "POST"; r.httpBody = try JSONEncoder().encode(command)
                r.setValue(base, forHTTPHeaderField: "Origin"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data,response) = try await URLSession.shared.data(for: r)
            return (data,(response as! HTTPURLResponse).statusCode)
        }
        let (data,code) = try await request("/api/status?platform=bilibili")
        let snapshot = try #require(JSONSerialization.jsonObject(with: data) as? [String:Any])
        #expect(code == 200 && snapshot["platform"] as? String == "bilibili" && snapshot["canWrite"] as? Bool == true)
        let (_,unknown) = try await request("/api/status?platform=unknown"); #expect(unknown == 400)
        var save = command(xhs, "save"); var settings = xhs.stored.settings; settings.keyword = "小红书独立任务"; save.settings = settings; save.platform = .xiaohongshu
        let (_,queued) = try await request("/api/action?platform=xiaohongshu", command: save); #expect(queued == 202)
        var crossed = save; crossed.platform = .bilibili
        let (_,denied) = try await request("/api/action?platform=bilibili", command: crossed); #expect(denied == 409)
        let (wrongJob,_) = try await request("/api/job/\(save.requestID.uuidString.lowercased())?platform=bilibili")
        #expect(String(decoding: wrongJob, as: UTF8.self).contains("unknown"))
        for _ in 0..<30 {
            if xhs.stored.settings.keyword == settings.keyword { break }; await Task.yield()
        }
        #expect(xhs.stored.settings.keyword == settings.keyword && bili.stored.settings.keyword != settings.keyword)
        try await xhs.perform(command(xhs, "reportWarning"))
        #expect(xhs.stored.warningAt != nil && bili.stored.warningAt == nil)
    }

    @Test func bothPlatformsAutoRunWithBoundedDefaultsAndKeepSavedModes() async throws {
        let defaults = SocialSettings()
        try defaults.validate()
        #expect(defaults.mode == .auto && defaults.personality == .natural && defaults.memoryEnabled == true)
        #expect(defaults.durationMinutes == 15 && defaults.maxPosts == 5 && defaults.maxModelCalls == 5)
        #expect(defaults.dailyWriteLimit == 3 && defaults.intervalSeconds == 300 && defaults.readIntervalSeconds == 60 && defaults.maxCharacters == 80)
        for platform in SocialPlatform.allCases {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let site = SocialSiteFixture(); site.post.platform = platform
            var e: SocialEngine? = try await prepare(dir, site: site, platform: platform)
            #expect(e!.stored.settings.mode == .auto && !e!.running && site.writes == 0)
            var settings = e!.stored.settings; settings.dailyWriteLimit = 1
            var save = command(e!, "save"); save.settings = settings; try await e!.perform(save)
            try await e!.perform(command(e!, "start"))
            for _ in 0..<500 {
                if !e!.running && !e!.busy { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            #expect(!e!.running && !e!.busy && site.writes == 1 && e!.attemptsToday == 1)
            #expect(e!.stored.records.last?.state == .confirmed && e!.stored.modelAttempts == 1)
            let reads = site.reads
            await #expect(throws: (any Error).self) { try await e!.perform(command(e!, "start")) }
            #expect(site.writes == 1 && site.reads == reads && !e!.running)
            settings.mode = .review; settings.keyword = "保留自定义主题"
            save = command(e!, "save"); save.settings = settings; try await e!.perform(save)
            e!.shutdown(); e = nil
            let reopened = SocialEngine(platform: platform, directory: dir, adapter: site)
            #expect(reopened.stored.settings.mode == .review && reopened.stored.settings.keyword == settings.keyword)
            #expect(!reopened.running && reopened.attemptsToday == 1)
            reopened.shutdown()
        }
    }

    @Test func receiptWarningPausesWithoutErasingAcceptance() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let site = SocialSiteFixture(); site.receiptWarning = true; site.post.platform = .bilibili
        let e = try await prepare(dir, site: site, platform: .bilibili)
        try await e.perform(command(e, "draft"))
        let draft = try #require(e.stored.records.last)
        try await e.perform(command(e, "approve", record: draft))
        #expect(e.stored.records.last?.state == .accepted && e.stored.warningAt != nil && !e.running)
        #expect(site.writes == 1 && e.attemptsToday == 1 && e.blockingCount == 0)
    }
}
