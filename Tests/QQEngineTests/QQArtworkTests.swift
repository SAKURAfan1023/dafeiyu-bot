import Foundation
import Testing
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import BotCore
@testable import WeChatAIBot

final class ArtworkFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var paths: [String] = []
    private static var holdImage = false
    private static var badImage = false
    private static var originalStatus = 200
    private static var paginated = false
    private static var longPortfolio = false
    private static var deepSearch = false
    static func extendSearch() { lock.lock(); deepSearch = true; lock.unlock() }
    private static var qualityPopular = false
    static func enablePopular() { lock.lock(); qualityPopular = true; lock.unlock() }
    static func paginate() { lock.lock(); paginated = true; lock.unlock() }
    static func extendPortfolio() { lock.lock(); longPortfolio = true; lock.unlock() }
    static func setOriginalStatus(_ value: Int) { lock.lock(); originalStatus = value; lock.unlock() }
    static func delayImage() { lock.lock(); holdImage = true; lock.unlock() }
    static func corruptImages() { lock.lock(); badImage = true; lock.unlock() }
    static var calls: [String] { lock.lock(); defer { lock.unlock() }; return paths }
    static func reset() { lock.lock(); paths = []; holdImage = false; badImage = false; originalStatus = 200; paginated = false; longPortfolio = false; qualityPopular = false; deepSearch = false; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    static func photo() -> Data {
        let context = CGContext(data: nil, width: 1600, height: 900, bitsPerComponent: 8, bytesPerRow: 6400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        let data = NSMutableData(), dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil); CGImageDestinationFinalize(dest); return data as Data
    }
    override func startLoading() {
        let u = request.url!; Self.lock.lock(); Self.paths.append(u.absoluteString); Self.lock.unlock()
        Self.lock.lock(); let hold = Self.holdImage, bad = Self.badImage, originalStatus = Self.originalStatus, paginated = Self.paginated, longPortfolio = Self.longPortfolio, qualityPopular = Self.qualityPopular, deepSearch = Self.deepSearch; Self.lock.unlock()
        if u.host == "i.pximg.net" && hold { return }
        var object: [String: Any] = [:], data: Data?, code = 200
        if u.host == "api.deepseek.com" {
            var bytes = request.httpBody ?? Data()
            if bytes.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 8192)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(contentsOf: buffer.prefix(n)) }
            }
            let body = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            if let definitions = body["tools"] as? [[String: Any]] {
                #expect(definitions.contains { ($0["function"] as? [String: Any])?["name"] as? String == "find_artwork" })
                object = ["choices": [["message": ["content": NSNull(), "tool_calls": [["id": "art-test", "type": "function", "function": ["name": "find_artwork", "arguments": "{\"mode\":\"featured\",\"query\":\"初音未来\"}"]]]], "finish_reason": "tool_calls"]]]
            } else {
                object = ["choices": [["message": ["content": "{\"text\":\"给你看看这张。\",\"emotion\":\"joy\",\"intensity\":1}"], "finish_reason": "stop"]]]
            }
        } else if u.path == "/ranking.php" {
            object = ["date": "20260927", "contents": [101, 105, 106, 107].enumerated().map { index, id in ["illust_id": id, "title": "测试插画", "rank": index + 1, "user_id": id == 101 ? 17429 : id == 107 ? 27517 : 688570, "tags": ["女の子", "オリジナル"], "illust_content_type": ["sexual": 0, "lo": false, "grotesque": false]] as [String: Any] }]
            if paginated {
                let second = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "p" && $0.value == "2" } == true
                object["next"] = second ? false : 2
                if second { object["contents"] = [["illust_id": 108, "title": "原神 白发猫耳", "rank": 51, "user_id": 999888, "tags": ["女の子", "原神", "白髪", "猫耳"], "illust_content_type": ["sexual": 0, "lo": false, "grotesque": false]]] }
            }
            object["contents"] = (object["contents"] as! [[String: Any]]).reversed().map { $0 }
        } else if u.path.contains("/illusts/tag") || u.path.hasPrefix("/ajax/search/illustrations/") {
            let search = u.path.hasPrefix("/ajax/search/illustrations/")
            let params = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems ?? []
            let word = params.first { $0.name == (search ? "word" : "tag") }?.value ?? ""
            let offset = Int(params.first { $0.name == "offset" }?.value ?? "0") ?? 0
            var ids = search ? (word == "初音ミク" ? [53325959] : [300, 301]) : u.path.contains("688570") ? [53325959] : u.path.contains("999111") ? [103] : [102, 101]
            if word.contains("不存在") || (!search && word == "白髪") { ids = [] }
            if deepSearch && search { ids = Array(300...319) }
            if longPortfolio && !search { ids = offset == 0 ? Array((201...230).reversed()) : [200] }
            let rows = ids.map { id -> [String: Any] in
                ["id": String(id), "title": "测试作品", "userId": id == 103 ? "999111" : id >= 300 && id < 400 ? "999888" : id == 53325959 ? "688570" : "17429", "userName": "Fixture Artist", "illustType": 0, "xRestrict": 0, "aiType": 1, "isUnlisted": false, "width": 1600, "height": 900, "tags": ["女の子", "オリジナル"]]
            }
            if search {
                let results: [String: Any] = ["data": rows, "total": rows.count, "lastPage": 1]
                var body: [String: Any] = ["illust": results]
                if qualityPopular, let prototype = rows.first {
                    let recommendations = [302, 303, 304, 300].map { id -> [String: Any] in
                        var row = prototype; row["id"] = String(id); row["tags"] = ["原神100000users入り"]; return row
                    }
                    body["popular"] = ["permanent": recommendations, "recent": recommendations]
                }
                object = ["error": false, "body": body]
            } else {
                let results: [String: Any] = ["works": rows, "total": longPortfolio ? 31 : rows.count]
                object = ["error": false, "body": results]
            }
            if search {
                #expect(params.contains { $0.name == "mode" && $0.value == "safe" })
                #expect(params.contains { $0.name == "ai_type" && $0.value == "1" })
            }
        } else if u.path.hasPrefix("/ajax/illust/") {
            let id = u.lastPathComponent
            object = ["error": false, "body": ["id": id, "illustTitle": "风景 \(id)", "userName": "Fixture Artist", "userId": id == "103" ? "999111" : QQArtworkLibrary.featuredIDs.contains(id) || ["105", "106"].contains(id) ? "688570" : "17429", "xRestrict": 0, "aiType": 1, "illustType": 0, "isUnlisted": false, "width": 1600, "height": 900, "urls": ["original": "https://i.pximg.net/img-original/\(id).jpg", "regular": "https://i.pximg.net/img-master/\(id).jpg"], "tags": ["tags": [["tag": "女の子"], ["tag": "オリジナル"]]]]]
            if id == "108" {
                var body = object["body"] as! [String: Any]; body["userId"] = "999888"
                body["tags"] = ["tags": ["女の子", "原神", "白髪", "猫耳"].map { ["tag": $0] }]; object["body"] = body
            }
            if ["101", "300", "301"].contains(id) {
                var body = object["body"] as! [String: Any]
                body["tags"] = ["tags": [["tag": "男性"], ["tag": "風景"]]]
                if id == "101" { body["width"] = 900; body["height"] = 600 }
                if id != "101" { body["userId"] = "999888" }
                object["body"] = body
            }
            if let count = ["300": 2500, "301": 3500, "303": 999, "304": 1000, "319": 5000][id] {
                var body = object["body"] as! [String: Any]
                body["bookmarkCount"] = count; body["likeCount"] = 800; body["viewCount"] = 10000
                object["body"] = body
            }
            if longPortfolio, let number = Int(id), number > 200 {
                var body = object["body"] as! [String: Any]; body["xRestrict"] = 1; object["body"] = body
            }
        } else if u.path.hasPrefix("/ajax/user/") {
            object = ["error": u.path.contains("999112"), "body": ["userId": u.lastPathComponent, "name": "新增画师", "comment": u.path.contains("688570") ? "商業目的ではない場合、2次加工が可能です。ソースくらいは残してください！" : u.path.contains("999111") ? "Noncommercial sharing with credit allowed." : "Reprint is prohibited."]]
        }
        else if u.host == "i.pximg.net" {
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.pixiv.net/")
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            let original = u.path.hasPrefix("/img-original/")
            code = original && originalStatus > 0 ? originalStatus : 200
            data = original && originalStatus == -2 ? Data(repeating: 0, count: 20_000_001) : bad || (original && originalStatus == -1) ? Data("not an image".utf8) : Self.photo()
        }
        else { code = 500; Issue.record("Unexpected artwork endpoint") }
        data = data ?? (try! JSONSerialization.data(withJSONObject: object))
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: u, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data!); client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) @MainActor struct QQArtworkIntegrationTests {
    @Test func sourceSearchSelectsReturnedResultsWithoutScanningArtists() async throws {
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        var config = QQArtworkConfig(); config.enabled = true; config.pixivArtistIDs = []
        var ledger = QQArtworkLedger(), count = 0
        #expect(QQArtworkLibrary.searchQuery("初音未来 白发 不要黑丝") == "初音ミク 白髪 -黒タイツ")
        let first = try await library.prepare(.init(mode: "featured", query: "白发 猫耳"), config: config, scope: "A", ledger: ledger, beforeFetch: { count += 1 })
        #expect(first.id == "pixiv:300"); #expect(first.image != nil); #expect(count == 3)
        // Fixture details intentionally lack these keywords and contain a male/landscape subject.
        #expect(ArtworkFixtureProtocol.calls.contains { $0.contains("/ajax/search/illustrations/") })
        #expect(ArtworkFixtureProtocol.calls.filter { $0.contains("/ajax/illust/") }.count == 1)
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("/ajax/user/") || $0.contains("ranking.php") })
        ledger.reserve(ticket: UUID(), scope: "A", id: first.id!, hash: nil, request: first.request)
        let next = try await library.prepare(.init(mode: "next"), config: config, scope: "A", ledger: ledger, beforeFetch: { count += 1 })
        #expect(next.id == "pixiv:301"); #expect(count == 5) // Cached result page, only next detail + image.
        #expect(next.request.query == "白发 猫耳")
        #expect(QQArtworkLibrary.allowedURL("https://www.pixiv.net.evil.org/ajax/search/illustrations/a") == nil)
    }
    @Test func qualitySearchVerifiesCountsBeforeDownloadingAndContinues() async throws {
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        ArtworkFixtureProtocol.enablePopular()
        var config = QQArtworkConfig(); config.enabled = true; config.pixivArtistIDs = []
        var ledger = QQArtworkLedger()
        let result = try await library.prepare(.init(mode: "search", query: "原神"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(result.id == "pixiv:304"); #expect(result.image != nil)
        #expect(result.caption.contains("收藏 1000 · 点赞 800 · 浏览 10000"))
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("ranking.php") || $0.contains("/ajax/user/") })
        #expect(ArtworkFixtureProtocol.calls.filter { $0.contains("pximg.net") }.count == 1)
        #expect(ArtworkFixtureProtocol.calls.filter { $0.contains("/ajax/illust/") }.count == 3) // Missing count and exaggerated user tag cannot qualify.
        ledger.reserve(ticket: UUID(), scope: "A", id: result.id!, hash: nil, request: result.request)
        let next = try await library.prepare(.init(mode: "next"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(next.id == "pixiv:300"); #expect(next.request == result.request)
        let other = try await library.prepare(.init(mode: "search", query: "原神"), config: config, scope: "B", ledger: ledger, beforeFetch: {})
        #expect(other.id == "pixiv:304")
        config.effectiveSearchMinBookmarks = 5000
        let empty = try await library.prepare(result.request, config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(empty.image == nil); #expect(empty.caption.contains("收藏 ≥ 5000"))
        config.effectiveSearchMinBookmarks = 3000
        let lower = try await library.prepare(result.request, config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(lower.id == "pixiv:301") // Threshold changes must invalidate rejection decisions.
        #expect(QQArtworkLibrary.toolRequest("{\"mode\":\"search\",\"query\":\"原神\"}")?.mode == "search")
    }
    @Test func qualitySearchBudgetContinuesWithoutRepeatingRejectedDetails() async throws {
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        ArtworkFixtureProtocol.extendSearch()
        var config = QQArtworkConfig(); config.enabled = true; config.effectiveSearchMinBookmarks = 4000
        var ledger = QQArtworkLedger()
        let first = try await library.prepare(.init(mode: "search", query: "原神"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(first.image == nil); #expect(first.caption.contains("12 个候选")); #expect(first.caption.contains("4000"))
        #expect(ArtworkFixtureProtocol.calls.filter { $0.contains("/ajax/illust/") }.count == 12)
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("pximg.net") })
        ledger.continuation["A"] = first.request
        let next = try await library.prepare(.init(mode: "next"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(next.id == "pixiv:319")
        let details = ArtworkFixtureProtocol.calls.filter { $0.contains("/ajax/illust/") }
        #expect(details.count == 20); #expect(Set(details).count == 20)
    }
    @Test func liveQualitySearchWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["QQ_QUALITY_SEARCH_PROBE"] == "1" else { return }
        var config = QQArtworkConfig(); config.enabled = true; config.pixivArtistIDs = []
        var calls = 0
        let start = Date()
        let result = try await QQArtworkLibrary().prepare(.init(mode: "search", query: "原神"), config: config, scope: "probe", ledger: .init(), beforeFetch: {
            calls += 1; if calls > 15 { throw AppFailure.message("Live probe budget exhausted") }
        })
        try #require(result.image != nil)
        #expect(result.caption.contains("收藏 ≥ 1000")); #expect(result.caption.contains("点赞"))
        print("QUALITY_SEARCH_PROBE sourceRequests=\(calls) seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) imageBytes=\(result.image!.count) threshold=1000 noQQ=true noModel=true")
    }
    @Test func liveFastSearchAndFirstRankWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["QQ_FAST_ART_PROBE"] == "1" else { return }
        let library = QQArtworkLibrary()
        var config = QQArtworkConfig(); config.enabled = true; config.pixivArtistIDs = []
        var ledger = QQArtworkLedger(), count = 0
        for (index, request) in [QQArtworkRequest(mode: "hot"), .init(mode: "next"), .init(mode: "featured", query: "原神")].enumerated() {
            let start = Date(), before = count
            let result = try await library.prepare(request, config: config, scope: "probe", ledger: ledger, beforeFetch: {
                count += 1; if count > 15 { throw AppFailure.message("Live probe budget exhausted") }
            })
            try #require(result.image != nil); try #require(result.id != nil)
            if index == 0 { #expect(result.caption.contains("第 1 名")) }
            if index == 1 { #expect(result.caption.contains("第 2 名")) }
            if index == 2 { #expect(result.caption.contains("关键词搜索")) }
            ledger.reserve(ticket: UUID(), scope: "probe", id: result.id!, hash: result.hash, request: result.request)
            print("FAST_ART_PROBE step=\(index) sourceRequests=\(count - before) seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) imageBytes=\(result.image!.count) noQQ=true noModel=true")
        }
    }
    @Test func nextSkipsAlreadyRejectedPortfolioCandidates() async throws {
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        ArtworkFixtureProtocol.extendPortfolio()
        var config = QQArtworkConfig(); config.enabled = true
        var ledger = QQArtworkLedger()
        let first = try await library.prepare(.init(mode: "artist", query: "LAM"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(first.image == nil); #expect(first.caption.contains("30 个候选"))
        ledger.continuation["A"] = first.request
        let before = ArtworkFixtureProtocol.calls.count
        let next = try await library.prepare(.init(mode: "next"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(next.id == "pixiv:200"); #expect(next.image != nil)
        #expect(ArtworkFixtureProtocol.calls.count - before == 2) // One new detail and one picture; no rescanning the rejected head.
    }
    @Test func nextContinuesPastFeaturedAndRankingWithoutChangingIntent() async throws {
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        var config = QQArtworkConfig(); config.enabled = true; config.pixivArtistIDs = ["17429"]
        var ledger = QQArtworkLedger()
        for id in QQArtworkLibrary.featuredIDs {
            ledger.reserve(ticket: UUID(), scope: "A", id: "pixiv:" + id, hash: nil, request: .init(mode: "featured"))
        }
        let next = try await library.prepare(.init(mode: "next"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(["pixiv:101", "pixiv:102"].contains(next.id ?? "")); #expect(next.image != nil)
        #expect(next.request == .init(mode: "featured"))
        let unmatched = try await library.prepare(.init(mode: "next", query: "不存在的角色"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(unmatched.image == nil); #expect(unmatched.request.query == "不存在的角色")
        ArtworkFixtureProtocol.paginate()
        for id in [101, 105, 106, 107] { ledger.reserve(ticket: UUID(), scope: "B", id: "pixiv:\(id)", hash: nil, request: .init(mode: "hot")) }
        // Ranking artist 999888 is not configured; it must still be available at rank 51.
        let ranked = try await library.prepare(.init(mode: "next"), config: config, scope: "B", ledger: ledger, beforeFetch: {})
        #expect(ranked.id == "pixiv:108"); #expect(ranked.image != nil); #expect(ranked.request.mode == "hot")
        #expect(ranked.caption.contains("第 51 名")); #expect(ranked.caption.contains("/artist 999888"))
        #expect(ArtworkFixtureProtocol.calls.contains { $0.contains("p=2&date=20260927") })
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("deepseek") })
    }
    @Test func promptsAreConjunctiveAndArtistContinuationStaysScoped() async throws {
        #expect(QQArtworkLibrary.matches("来一张白发猫耳的美少女", in: ["白髪", "猫耳", "女の子"]))
        #expect(!QQArtworkLibrary.matches("白发 猫耳", in: ["黒髪", "猫耳"]))
        #expect(QQArtworkLibrary.matches("白发 不要黑丝", in: ["白髪", "メイド"]))
        #expect(!QQArtworkLibrary.matches("白发 -黑丝", in: ["白髪", "黒タイツ"]))
        #expect(QQArtworkLibrary.matches("初音未来", in: ["初音ミク"]))
        #expect(!QQArtworkLibrary.matches("不存在的角色", in: ["女の子", "原神"]))
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        var config = QQArtworkConfig(); config.enabled = true
        var ledger = QQArtworkLedger()
        let first = try await library.prepare(.init(mode: "artist", query: "LAM オリジナル"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(first.id == "pixiv:102"); #expect(first.request.query == "17429"); #expect(first.request.prompt == "オリジナル")
        ledger.reserve(ticket: UUID(), scope: "A", id: first.id!, hash: nil, request: first.request)
        let blocked = try await library.prepare(.init(mode: "next", query: "白发"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(blocked.image == nil); #expect(blocked.request.query == "17429"); #expect(blocked.request.prompt == "白发")
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("ranking.php") || $0.contains("user/688570") })
    }
    @Test func hotNeverFallsBackToConfiguredPortfolios() async throws {
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        var config = QQArtworkConfig(); config.enabled = true
        var ledger = QQArtworkLedger()
        for id in [101, 105, 106, 107] { ledger.reserve(ticket: UUID(), scope: "A", id: "pixiv:\(id)", hash: nil, request: .init(mode: "hot")) }
        let result = try await library.prepare(.init(mode: "next"), config: config, scope: "A", ledger: ledger, beforeFetch: {})
        #expect(result.image == nil); #expect(result.caption.contains("不限制画师"))
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("/ajax/user/") || $0.contains("pximg.net") })
    }
    @Test func liveRankingContinuationWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["QQ_NEXT_ART_PROBE"] == "1" else { return }
        var config = QQArtworkConfig(); config.enabled = true; config.pixivArtistIDs = []
        var ledger = QQArtworkLedger(), calls = 0
        let library = QQArtworkLibrary()
        let first = try await library.prepare(.init(mode: "hot"), config: config, scope: "probe", ledger: ledger, beforeFetch: { calls += 1; if calls > 70 { throw AppFailure.message("Probe budget exhausted") } })
        try #require(first.image != nil); try #require(first.id != nil)
        ledger.reserve(ticket: UUID(), scope: "probe", id: first.id!, hash: first.hash, request: first.request)
        let second = try await library.prepare(.init(mode: "next"), config: config, scope: "probe", ledger: ledger, beforeFetch: { calls += 1; if calls > 70 { throw AppFailure.message("Probe budget exhausted") } })
        try #require(second.image != nil); #expect(second.id != first.id)
        #expect(first.caption.contains("Pixiv 日榜")); #expect(second.caption.contains("Pixiv 日榜"))
        print("LIVE_HOT_NEXT distinctImages=2 configuredArtists=0 requests=\(calls) noQQ=true noModel=true")
    }
    @Test(arguments: [200, 404, 410, -1, -2, 401, 403, 429, 500])
    func publicAssetVariantsAreBoundedAndRespectAccessFailures(_ status: Int) async throws {
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        ArtworkFixtureProtocol.setOriginalStatus(status)
        var config = QQArtworkConfig(); config.enabled = true; config.imagePermissions = [:]
        if [-2, 401, 403, 429, 500].contains(status) {
            do {
                _ = try await library.prepare(.init(mode: "artist", query: "LAM"), config: config, scope: "A", ledger: .init(), beforeFetch: {})
                Issue.record("Unavailable source must not return a link-only work")
            } catch { #expect(!(error is CancellationError)) }
            #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("/img-master/") })
            #expect(ArtworkFixtureProtocol.calls.filter { $0.contains("pximg.net") }.count == 1)
        } else {
            let result = try await library.prepare(.init(mode: "artist", query: "LAM"), config: config, scope: "A", ledger: .init(), beforeFetch: {})
            #expect(result.image != nil); #expect(result.id == "pixiv:102")
            #expect(ArtworkFixtureProtocol.calls.filter { $0.contains("pximg.net") }.count == (status == 200 ? 1 : 2))
            #expect(ArtworkFixtureProtocol.calls.contains { $0.contains("/img-master/") } == (status != 200))
        }
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("?full=1") || $0.contains("deepseek") })
        #expect(QQArtworkLibrary.allowedURL("https://i.pximg.net.evil.org/img-master/1.jpg") == nil)
        #expect(QQArtworkLibrary.allowedURL("https://127.0.0.1/img-master/1.jpg") == nil)
    }
    @Test func livePublicArtistPictureWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["QQ_PUBLIC_ART_PROBE"] == "1" else { return }
        var config = QQArtworkConfig(); config.enabled = true; config.imagePermissions = [:]
        var calls = 0
        let result = try await QQArtworkLibrary().prepare(.init(mode: "artist", query: "Anmi"), config: config, scope: "probe", ledger: .init(), beforeFetch: { calls += 1 })
        try #require(result.image != nil)
        #expect(result.caption.contains("/next")); #expect(result.caption.contains("/artist 212801"))
        print("PUBLIC_ARTIST_PROBE imageBytes=\(result.image!.count) sourceRequests=\(calls) noLicenseRegistry=true noQQ=true noModel=true")
    }
    @Test func artistManagementPersistsListsAndResolvesNamesWithoutModelCalls() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, artworkLibrary: library)
        engine.config.effectiveArtwork.enabled = true
        let before = engine.config.effectiveArtwork
        await engine.addArtworkArtist("https://www.pixiv.net/artworks/999111")
        #expect(engine.config.effectiveArtwork == before); #expect(ArtworkFixtureProtocol.calls.isEmpty)
        await engine.addArtworkArtist("https://www.pixiv.net/users/999111")
        #expect(engine.error == nil); #expect(engine.config.effectiveArtwork.artistNames?["999111"] == "新增画师")
        #expect(engine.config.effectiveArtwork.imagePermissions["999111"] == nil)
        #expect(engine.artworkLedger.networkCalls == 1); #expect(engine.usage.calls == 0); #expect(engine.sends.attempts == 0)
        let restored = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(restored.config.effectiveArtwork.artistNames?["999111"] == "新增画师")
        await engine.addArtworkArtist("999111")
        #expect(engine.error?.contains("重复") == true); #expect(ArtworkFixtureProtocol.calls.count == 1)
        await engine.addArtworkArtist("999112")
        #expect(!engine.config.effectiveArtwork.pixivArtistIDs.contains("999112"))
        let settings = engine.config.effectiveArtwork
        let unlicensed = try await library.prepare(.init(mode: "artist", query: "新增画师"), config: settings, scope: "A", ledger: .init(), beforeFetch: {})
        #expect(unlicensed.id == "pixiv:103"); #expect(unlicensed.image != nil)
        #expect(settings.imagePermissions["999111"] == nil)
        let roster = try await library.prepare(.init(mode: "artists"), config: settings, scope: "A", ledger: .init(), beforeFetch: { Issue.record("Roster must be local") })
        #expect(roster.caption.contains("新增画师")); #expect(roster.caption.contains("/artist 999111"))
        let artwork = try await library.prepare(.init(mode: "artist", query: "新增画师"), config: settings, scope: "A", ledger: .init(), beforeFetch: {})
        #expect(artwork.id == "pixiv:103"); #expect(artwork.image != nil)
        var ambiguous = settings; ambiguous.artistNames?["17429"] = "新增画师"
        let denied = try await library.prepare(.init(mode: "artist", query: "新增画师"), config: ambiguous, scope: "A", ledger: .init(), beforeFetch: { Issue.record("Ambiguous name must not fetch") })
        #expect(denied.caption.contains("同名")); #expect(denied.id == nil)
        var removed = settings
        removed.pixivArtistIDs.removeAll { $0 == "999111" }; removed.artistNames?.removeValue(forKey: "999111")
        engine.saveArtwork(removed); #expect(engine.error == nil)
        let direct = try await library.prepare(.init(mode: "artist", query: "999111"), config: engine.config.effectiveArtwork, scope: "A", ledger: .init(), beforeFetch: {})
        #expect(direct.id == "pixiv:103"); #expect(!engine.config.effectiveArtwork.pixivArtistIDs.contains("999111"))
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("deepseek") })
        let fetched = ArtworkFixtureProtocol.calls.count
        engine.config.effectiveArtwork.pixivArtistIDs = (100...119).map(String.init)
        await engine.addArtworkArtist("999113")
        #expect(engine.error?.contains("20") == true); #expect(ArtworkFixtureProtocol.calls.count == fetched)
    }
    func client() -> (QQArtworkLibrary, URLSession) {
        ArtworkFixtureProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ArtworkFixtureProtocol.self]
        let session = URLSession(configuration: config)
        return (QQArtworkLibrary(session: session, spacing: 0), session)
    }
    @Test func realSchemaRankingIsDatedAndNextIsScoped() async throws {
        let (client, session) = client(); defer { session.invalidateAndCancel() }
        var settings = QQArtworkConfig(); settings.enabled = true
        var ledger = QQArtworkLedger(), requests = 0
        let first = try await client.prepare(.init(mode: "hot"), config: settings, scope: "A", ledger: ledger, beforeFetch: { requests += 1 })
        #expect(first.id == "pixiv:101"); #expect(first.image != nil)
        #expect(first.caption.contains("20260927 · 第 1 名")); #expect(first.caption.contains("/next")); #expect(first.caption.contains("Fixture Artist"))
        ledger.reserve(ticket: UUID(), scope: "A", id: first.id!, hash: nil, request: first.request)
        let next = try await client.prepare(.init(mode: "next"), config: settings, scope: "A", ledger: ledger, beforeFetch: { requests += 1 })
        #expect(next.id == "pixiv:105"); #expect(next.image != nil)
        let isolated = try await client.prepare(.init(mode: "next"), config: settings, scope: "B", ledger: ledger, beforeFetch: { Issue.record("No network for absent continuation") })
        #expect(isolated.id == nil)
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("?full=1") })
    }
    @Test func publicPortfolioDoesNotRequireLicenseRegistry() async throws {
        let (client, session) = client(); defer { session.invalidateAndCancel() }
        var settings = QQArtworkConfig(); settings.enabled = true; settings.imagePermissions = [:]
        let result = try await client.prepare(.init(mode: "artist", query: "LAM"), config: settings, scope: "A", ledger: QQArtworkLedger(), beforeFetch: {})
        #expect(result.image != nil); #expect(result.id == "pixiv:102")
        #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("?full=1") })
    }
    @Test func publicImagesHaveAttributionAndStrictInputs() async throws {
        let (client, session) = client(); defer { session.invalidateAndCancel() }
        var settings = QQArtworkConfig(); settings.enabled = true
        let result = try await client.prepare(.init(mode: "featured", query: "初音未来"), config: settings, scope: "A", ledger: QQArtworkLedger(), beforeFetch: {})
        #expect(result.image != nil); #expect(result.hash?.count == 64)
        #expect(result.caption.contains("Fixture Artist")); #expect(result.caption.contains("https://www.pixiv.net/artworks/"))
        #expect(QQArtworkLibrary.allowedURL("https://www.peppercarrot.com.evil.org/0_sources/0ther/artworks/hi-res/a.jpg") == nil)
        #expect(QQArtworkLibrary.allowedURL("https://127.0.0.1/a.jpg") == nil)
        #expect(QQArtworkLibrary.toolRequest("{\"mode\":\"hot\",\"query\":\"x\",\"target\":\"other\"}") == nil)
        #expect(QQArtworkLibrary.excludedTags(["R-18"]))
        #expect(!QQArtworkLibrary.illustrationTitle("【新刊】東方衣替画録"))
        #expect(QQArtworkLibrary.animeGirl(tags: ["女の子", "原神"], artist: "999", id: "999"))
        #expect(!QQArtworkLibrary.animeGirl(tags: ["風景", "空"], artist: "17429", id: "999"))
        #expect(!QQArtworkLibrary.animeGirl(tags: ["女の子", "写真", "原神"], artist: "17429", id: "999"))
        #expect(!QQArtworkLibrary.animeGirl(tags: ["男性", "原神"], artist: "17429", id: "999"))
        #expect(throws: (any Error).self) { try QQArtworkLibrary.normalized(Data("bad image".utf8), config: settings) }
    }
    @Test(arguments: ["command", "qualitySearch", "compactHot", "hotPrompt", "artistPrompt", "nextHot", "nextFeatured", "nextPrompt", "noResultPrompt", "private", "owner", "foreign", "unknownSend", "agent", "agentWithoutLicense", "agentBadImage", "commandBadImage", "commandWithoutLicense", "artistWithoutLicense", "hotWithoutLicense", "schedule", "hourlySchedule", "scheduleNoImage", "scheduleFallback", "scheduleQueued", "paused", "quota", "downloadPause"])
    func engineRoutingAndSendGuards(_ mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("groupParticipation".utf8).write(to: directory.appendingPathComponent("message-shape"))
        if mode == "unknownSend" { try Data().write(to: directory.appendingPathComponent("drop-send")) }
        let server = Process(), output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path, directory.path]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let (library, session) = client(); defer { session.invalidateAndCancel() }
        if ["compactHot", "hotPrompt", "nextPrompt"].contains(mode) { ArtworkFixtureProtocol.paginate() }
        if ["downloadPause", "scheduleQueued"].contains(mode) { ArtworkFixtureProtocol.delayImage() }
        if ["agentBadImage", "commandBadImage"].contains(mode) { ArtworkFixtureProtocol.corruptImages() }
        if ["nextHot", "nextFeatured", "nextPrompt"].contains(mode) {
            let seed = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
            seed.config.expectedSelfID = "12345"; seed.save()
            let file = directory.appendingPathComponent("qq-state.json")
            var stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var ledger = QQArtworkLedger()
            ledger.continuation["12345:group:99999"] = .init(mode: mode == "nextFeatured" ? "featured" : "hot")
            stored["artworkLedger"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger))
            try JSONSerialization.data(withJSONObject: stored).write(to: file)
        }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, modelClient: DeepSeekClient(session: session), artworkLibrary: library)
        defer { engine.disconnect() }
        engine.config.endpoint = "ws://127.0.0.1:\(port)"; engine.config.expectedSelfID = "12345"
        engine.config.memoryEnabled = !["agent", "agentWithoutLicense", "agentBadImage"].contains(mode) // Commands must not queue memory learning even when enabled.
        engine.config.effectiveGroupParticipationEnabled = true; engine.config.effectiveGroupParticipationEvery = 10
        engine.config.effectiveImageGeneration.enabled = false; engine.config.effectivePersona.stickersEnabled = false
        engine.config.ai.cooldownSeconds = 1; engine.config.ai.effectiveSendLimits.globalIntervalSeconds = 1
        engine.config.effectiveArtwork.enabled = true
        if ["agentWithoutLicense", "commandWithoutLicense", "artistWithoutLicense", "hotWithoutLicense"].contains(mode) { engine.config.effectiveArtwork.imagePermissions = [:] }
        #expect(engine.useTemporaryCredentials(token: "synthetic-test-token", key: "synthetic-key"))
        await engine.connect(); try #require(engine.connected)
        let privateChat = mode == "private"
        engine.add(try #require(engine.contacts.first { $0.number == (privateChat ? "54321" : "99999") }))
        engine.config.targets[0].enabled = true
        if mode == "quota" { engine.config.effectiveArtwork.dailyPerChat = 1 }
        engine.start()
        if mode == "command" {
            let previous = engine.config.effectiveArtwork
            await engine.addArtworkArtist("999111")
            #expect(engine.config.effectiveArtwork == previous); #expect(engine.error?.contains("暂停") == true)
            #expect(ArtworkFixtureProtocol.calls.isEmpty); engine.error = nil
        }
        if mode == "paused" { engine.pause() }
        let scheduled = ["schedule", "hourlySchedule", "scheduleNoImage", "scheduleFallback"].contains(mode)
        if scheduled {
            let future = Date().addingTimeInterval(65), parts = Calendar.current.dateComponents([.hour, .minute], from: future)
            engine.config.effectiveArtwork.scheduleEnabled = true; engine.config.effectiveArtwork.scheduleHour = parts.hour!
            engine.config.effectiveArtwork.scheduleMinute = parts.minute!; engine.config.effectiveArtwork.scheduleTimeZone = TimeZone.current.identifier
            engine.config.effectiveArtwork.scheduleTargets = ["group:99999"]; engine.config.effectiveArtwork.scheduleMode = "featured"
            if mode == "hourlySchedule" { engine.config.effectiveArtwork.scheduleFrequency = "hourly" }
            if mode == "scheduleNoImage" { engine.config.effectiveArtwork.minLongEdge = 4096; engine.config.effectiveArtwork.minShortEdge = 4096 }
            if mode == "scheduleFallback" { engine.config.effectiveArtwork.scheduleMode = "hot" }
            engine.scheduleArtworks(now: future); engine.scheduleArtworks(now: future)
        } else {
            let commands = ["qualitySearch": "/search 原神", "compactHot": "/hot原神", "hotPrompt": "/hot 原神 白发 猫耳 -黑丝", "artistPrompt": "/artist LAM オリジナル", "nextHot": "/next", "nextFeatured": "/next", "nextPrompt": "/next 原神 白发", "noResultPrompt": "/art 不存在的角色"]
            let text = commands[mode] ?? (["agent", "agentWithoutLicense", "agentBadImage"].contains(mode) ? "想看看精选插画" : mode == "hotWithoutLicense" ? "/hot" : mode == "artistWithoutLicense" ? "/artist LAM" : "/art 初音未来")
            var segments: [[String: Any]] = [["type": "text", "data": ["text": text]]]
            if ["agent", "agentWithoutLicense", "agentBadImage"].contains(mode) { segments.insert(["type": "at", "data": ["qq": "12345"]], at: 0) }
            let owner = mode == "owner"
            let event: [String: Any] = ["post_type": owner ? "message_sent" : "message", "self_id": 12345, "user_id": owner ? 12345 : 54321,
                "sender": ["user_id": owner ? 12345 : 54321], "message_type": privateChat ? "private" : "group", "sub_type": privateChat ? "friend" : "normal", "group_id": mode == "foreign" ? 88888 : 99999, "message_id": 1, "message": segments]
            try JSONSerialization.data(withJSONObject: [event]).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
        }
        if ["downloadPause", "scheduleQueued"].contains(mode) {
            let until = Date().addingTimeInterval(3)
            while Date() < until && !ArtworkFixtureProtocol.calls.contains(where: { $0.contains("pximg.net") }) { try await Task.sleep(nanoseconds: 20_000_000) }
            try #require(ArtworkFixtureProtocol.calls.contains { $0.contains("pximg.net") })
            if mode == "scheduleQueued" {
                let future = Date().addingTimeInterval(65)
                engine.config.effectiveArtwork.scheduleEnabled = true
                engine.config.effectiveArtwork.scheduleFrequency = "hourly"
                engine.config.effectiveArtwork.scheduleTimeZone = TimeZone.current.identifier
                engine.config.effectiveArtwork.scheduleMinute = Calendar.current.component(.minute, from: future)
                engine.config.effectiveArtwork.scheduleTargets = ["group:99999"]
                engine.scheduleArtworks(now: future); engine.scheduleArtworks(now: future)
                #expect(engine.queuedCount == 1); #expect(engine.artworkLedger.schedules.count == 1)
            }
            engine.pause(); #expect(engine.queuedCount == 0)
        }
        let deadline = Date().addingTimeInterval(["foreign", "paused", "downloadPause", "scheduleNoImage", "scheduleQueued"].contains(mode) ? 0.5 : 5)
        while Date() < deadline && engine.sends.confirmed == 0 && engine.sends.uncertain == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        if ["foreign", "paused"].contains(mode) {
            #expect(engine.sends.attempts == 0); #expect(ArtworkFixtureProtocol.calls.isEmpty)
        } else if mode == "scheduleNoImage" {
            #expect(engine.sends.attempts == 0); #expect(engine.artworkLedger.schedules.count == 1)
            #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("pximg.net") })
        } else if ["downloadPause", "scheduleQueued"].contains(mode) {
            #expect(engine.sends.attempts == 0); #expect(!engine.running)
        } else if ["agentBadImage", "commandBadImage", "noResultPrompt"].contains(mode) {
            #expect(engine.sends.confirmed == 1); #expect(engine.artworkLedger.deliveries.isEmpty)
            let payload = try String(contentsOf: directory.appendingPathComponent("payload"), encoding: .utf8)
            #expect(!payload.contains("https:")); #expect(!payload.contains("base64:"))
            #expect(!payload.contains("给你看看这张")); #expect(!payload.contains("pixiv.net"))
        } else if mode == "unknownSend" {
            #expect(engine.sends.uncertain == 1); #expect(!engine.running)
            #expect(engine.artworkLedger.deliveries.first?.state == "unknown")
        } else {
            #expect(engine.sends.confirmed == 1)
            #expect(engine.artworkLedger.deliveries.first?.state == "confirmed")
            let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("payload"))) as! [String: Any]
            let segments = payload["message"] as! [[String: Any]]
            #expect(segments.contains { $0["type"] as? String == "image" })
            #expect(segments.contains { (($0["data"] as? [String: String])?["text"] ?? "").contains("/next") })
            if mode == "qualitySearch" {
                #expect(segments.contains { (($0["data"] as? [String: String])?["text"] ?? "").contains("收藏 2500") })
                #expect(engine.artworkLedger.continuation["12345:group:99999"]?.mode == "search")
            }
            if scheduled {
                #expect(engine.artworkLedger.schedules.count == 1)
                #expect(segments.filter { $0["type"] as? String == "image" }.count == 1)
                #expect(segments.contains { (($0["data"] as? [String: String])?["text"] ?? "").contains("/artists") })
                engine.scheduleArtworks(now: Date().addingTimeInterval(65))
                #expect(engine.queuedCount == 0)
            }
        }
        if !["agent", "agentWithoutLicense", "agentBadImage"].contains(mode) {
            #expect(engine.usage.calls == 0); #expect(!ArtworkFixtureProtocol.calls.contains { $0.contains("deepseek.com") })
            #expect(engine.memoryBooks.isEmpty); #expect(engine.groupMessageCounts.values.allSatisfy { $0 == 0 })
        } else { #expect(engine.usage.calls == 3) }
        if mode == "quota" {
            let event: [String: Any] = ["post_type": "message", "self_id": 12345, "user_id": 54321, "sender": ["user_id": 54321], "message_type": "group", "sub_type": "normal", "group_id": 99999, "message_id": 2, "message": [["type": "text", "data": ["text": "/next"]]]]
            let networkBefore = ArtworkFixtureProtocol.calls.count
            try JSONSerialization.data(withJSONObject: [event]).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
            let until = Date().addingTimeInterval(3)
            while Date() < until && engine.sends.confirmed < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
            #expect(engine.sends.confirmed == 2); #expect(engine.artworkLedger.deliveries.count == 1)
            #expect(ArtworkFixtureProtocol.calls.count == networkBefore); #expect(engine.usage.calls == 0)
            let last = try String(contentsOf: directory.appendingPathComponent("payload"), encoding: .utf8)
            #expect(!last.contains("base64://"))
        }
        if mode == "noResultPrompt" {
            #expect(engine.artworkLedger.continuation["12345:group:99999"]?.query == "不存在的角色")
            let event: [String: Any] = ["post_type": "message", "self_id": 12345, "user_id": 54321, "sender": ["user_id": 54321], "message_type": "group", "sub_type": "normal", "group_id": 99999, "message_id": 2, "message": [["type": "text", "data": ["text": "/next 美少女"]]]]
            try JSONSerialization.data(withJSONObject: [event]).write(to: directory.appendingPathComponent("event-batch"), options: .atomic)
            let until = Date().addingTimeInterval(3)
            while Date() < until && engine.sends.confirmed < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
            #expect(engine.sends.confirmed == 2); #expect(engine.artworkLedger.deliveries.count == 1)
            #expect(engine.artworkLedger.continuation["12345:group:99999"]?.query == "美少女")
            #expect(engine.usage.calls == 0)
            let last = try String(contentsOf: directory.appendingPathComponent("payload"), encoding: .utf8)
            #expect(last.contains("base64://"))
        }
        engine.pause()
        let restored = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(restored.artworkLedger.deliveries.count == engine.artworkLedger.deliveries.count)
    }
    // Opt-in source smoke test. Never connects to QQ and never calls a model.
    @Test func liveScheduledPictureWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["QQ_HOURLY_LIVE_PROBE"] == "1" else { return }
        var config = QQArtworkConfig(); config.enabled = true
        var calls = 0
        let result = try await QQArtworkLibrary().prepare(.init(mode: "featured"), config: config, scope: "probe", ledger: .init(), randomArtist: true, beforeFetch: { calls += 1 })
        try #require(result.image != nil)
        #expect(result.caption.contains("/next")); #expect(result.caption.contains("/artists")); #expect(result.caption.contains("/artist "))
        print("HOURLY_PICTURE_PROBE imageBytes=\(result.image!.count) sourceRequests=\(calls) noQQ=true noModel=true")
    }
    @Test func liveArtistLookupWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["QQ_ARTIST_LIVE_PROBE"] == "1" else { return }
        var requests = 0
        let name = try await QQArtworkLibrary().lookupArtist("212801", beforeFetch: { requests += 1 })
        // Public display names can include current exhibition/publication suffixes.
        try #require(!name.isEmpty); #expect(requests == 1)
        print("ARTIST_PUBLIC_PROBE verified=true sourceRequests=\(requests) noQQ=true noModel=true")
    }
    @Test func livePublicSourcesWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["QQ_ARTWORK_LIVE_PROBE"] == "1" else { return }
        var settings = QQArtworkConfig(); settings.enabled = true
        let client = QQArtworkLibrary(); var networkCalls = 0
        let art = try await client.prepare(.init(mode: "featured", query: "初音未来"), config: settings, scope: "probe", ledger: QQArtworkLedger(), beforeFetch: { networkCalls += 1 })
        #expect(art.image != nil)
        let hot = try await client.prepare(.init(mode: "hot"), config: settings, scope: "probe", ledger: QQArtworkLedger(), beforeFetch: { networkCalls += 1 })
        #expect((hot.id == nil) == (hot.image == nil))
        if hot.id != nil { #expect(hot.caption.contains("Pixiv 日榜")) }
        else { #expect(!hot.caption.contains("https://")) }
        print("ARTWORK_PUBLIC_PROBE network=\(networkCalls) licensedImageBytes=\(art.image?.count ?? 0) hot=\(hot.id ?? "none") noQQ=true noModel=true")
    }
}
