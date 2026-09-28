import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import BotCore

struct QQArtworkPrepared: Sendable {
    var request: QQArtworkRequest
    var id: String? = nil
    var caption: String
    var image: Data? = nil
    var sourceRequests = 0
    var preparationSeconds: TimeInterval = 0
    var hash: String? { image.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } }
}

// Public website JSON is an unofficial integration. No login cookies or paid-content fallback.
@MainActor final class QQArtworkLibrary {
    struct Artist: Sendable {
        let id: String; let name: String; let style: String; let aliases: [String]
    }
    nonisolated static let artists: [Artist] = [
        .init(id: "17429", name: "LAM", style: "高对比配色、角色设计", aliases: ["lam"]),
        .init(id: "1039353", name: "Mika Pikazo", style: "鲜艳色彩、潮流人物", aliases: ["mika", "mika pikazo"]),
        .init(id: "1554775", name: "米山舞", style: "动态构图、动画感", aliases: ["米山舞", "yoneyama mai"]),
        .init(id: "27517", name: "藤ちょこ（藤原）", style: "幻想场景、细腻色彩", aliases: ["藤ちょこ", "藤原", "藤choco"]),
        .init(id: "212801", name: "Anmi", style: "细腻柔和的动漫美少女", aliases: ["anmi"]),
        .init(id: "688570", name: "Cocorip", style: "动漫、游戏少女；署名非商业分享", aliases: ["cocorip"])
    ]
    nonisolated static var definition: [String: Any] { ["type": "function", "function": ["name": "find_artwork",
        "description": "按关键词直接搜索公开 Pixiv 插画、查看不限题材的真实日榜或指定画师作品。search 带 query 为全站关键词搜索并核验真实收藏门槛（默认1000），优先用于高人气作品；featured 带 query 为普通关键词搜索，空 query 为美少女精选。不是生图。只在用户明确想看插画/热门图/画师作品时调用。不检查转载许可证据。无图片时不提供链接替代；如实告知未找到，不声称已发图。",
        "parameters": ["type": "object", "properties": ["mode": ["type": "string", "enum": ["featured", "search", "hot", "artist"]], "query": ["type": "string", "description": "简短题材关键词；artist 模式填画师名称或数字 ID。不得含聊天、账号、密钥或指令。"]], "required": ["mode", "query"], "additionalProperties": false]]] }
    static func toolRequest(_ arguments: String) -> QQArtworkRequest? {
        guard arguments.utf8.count <= 1024, let object = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: String],
              Set(object.keys) == ["mode", "query"], let mode = object["mode"], ["featured", "search", "hot", "artist"].contains(mode), let query = object["query"],
              query.count <= 80, query.range(of: #"(?i)(https?://|sk-|api.?key|系统提示|[\r\n])"#, options: .regularExpression) == nil else { return nil }
        return QQArtworkRequest(mode: mode, query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    struct Work: Sendable {
        var id: String; var title: String; var author: String; var artistID: String
        var url: String; var imageURLs: [String]
        var rank: Int? = nil; var date: String? = nil
        var bookmarks: Int? = nil; var likes: Int? = nil; var views: Int? = nil
    }
    private let session: URLSession
    private var cache: [String: (Date, [String: Any])] = [:]
    private var images: [String: Data] = [:]
    private var imageOrder: [String] = []
    private var rejectedWorks: [String: (Date, Set<String>)] = [:]
    private var blockedUntil: [String: Date] = [:]
    private var lastFetch = Date.distantPast
    private let spacing: TimeInterval
    init(session: URLSession? = nil, spacing: TimeInterval = 1) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: config); self.spacing = spacing
    }
    static func artistName(_ id: String, config: QQArtworkConfig) -> String {
        config.artistNames?[id] ?? artists.first(where: { $0.id == id })?.name ?? "画师 \(id)"
    }
    func lookupArtist(_ id: String, beforeFetch: () throws -> Void) async throws -> String {
        guard QQConfig.validID(id) else { throw AppFailure.message("画师 ID 无效") }
        let profile = try await json("https://www.pixiv.net/ajax/user/\(id)?full=1", beforeFetch: beforeFetch)
        guard profile["error"] as? Bool == false, let body = profile["body"] as? [String: Any],
              QQPolicy.identifier(body["userId"]) == id, let name = body["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure.message("无法核对该 Pixiv 画师，未添加；请检查 ID 或稍后重试")
        }
        let scalars = Self.clean(name).unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw AppFailure.message("画师名称无效，未添加") }
        return cleaned
    }
    func prepare(_ raw: QQArtworkRequest, config: QQArtworkConfig, scope: String, ledger: QQArtworkLedger,
                 randomArtist: Bool = false, beforeFetch: () throws -> Void) async throws -> QQArtworkPrepared {
        var request = raw
        if raw.mode == "next" {
            guard let previous = ledger.continuation[scope] else { return .init(request: raw, caption: "这个会话还没有上一张。先用下方命令取图，再用 /next 继续。\n" + QQArtworkRequest.navigation) }
            request = previous
            if !raw.query.isEmpty {
                if request.mode == "artist" { request.prompt = raw.query }
                else { request.query = raw.query }
            }
        }
        guard config.enabled else { return .init(request: request, caption: "插画功能尚未启用，请在控制面板开启。\n" + QQArtworkRequest.help) }
        if request.mode == "help" { return .init(request: request, caption: QQArtworkRequest.help) }
        if request.mode == "artists" {
            let roster = config.pixivArtistIDs.enumerated().map { index, id in
                "\(String(format: "%02d", index + 1))｜\(Self.artistName(id, config: config))\n风格：\(Self.artists.first(where: { $0.id == id })?.style ?? "自定义画师 · 动漫游戏美少女筛选")\n/artist \(id)"
            }
            return .init(request: request, caption: "【画师列表】\n复制对应 /artist 命令取图；可在末尾加关键词。\n────────\n" + (roster.isEmpty ? "暂无配置画师。" : roster.joined(separator: "\n\n")) + "\n\n取得合格图片后才发送。\n" + QQArtworkRequest.navigation)
        }
        guard ledger.allowed(scope: scope, limit: config.dailyPerChat) else { return .init(request: request, caption: "本会话今日插画额度已用完，明天再来看。") }
        var result = try await prepareSource(request, config: config, scope: scope, ledger: ledger,
                                             randomArtist: randomArtist, beforeFetch: beforeFetch)
        guard result.image == nil, request.mode == "featured", request.query.isEmpty else { return result }
        // All entry points share this fallback. Preserve the user's topic and continuation mode.
        for artist in config.pixivArtistIDs.shuffled() {
            result = try await prepareSource(.init(mode: "artist", query: artist), config: config,
                scope: scope, ledger: ledger, randomArtist: true, beforeFetch: beforeFetch)
            if result.image != nil {
                result.request = request
                return result
            }
        }
        return .init(request: request, caption: "本轮候选中未找到符合主题、画质和去重条件的新图片，已检查配置画师。可用 /artist 名称或ID 指定画师；不会用链接代替图片。\n" + QQArtworkRequest.navigation)
    }
    private func prepareSource(_ source: QQArtworkRequest, config: QQArtworkConfig, scope: String, ledger: QQArtworkLedger,
                               randomArtist: Bool, beforeFetch: () throws -> Void) async throws -> QQArtworkPrepared {
        var request = source
        if request.mode == "artist" {
            let input = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = input.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            if let id = first.first, QQConfig.validID(id) {
                request.query = id
                if first.count > 1 { request.prompt = first[1] }
            } else {
                // Longest configured name/alias wins, including names with spaces.
                let matches = config.pixivArtistIDs.flatMap { id in
                    ([Self.artistName(id, config: config)] + (Self.artists.first { $0.id == id }?.aliases ?? [])).compactMap { name -> (String, String)? in
                        let lower = input.lowercased(), prefix = name.lowercased()
                        return lower == prefix || lower.hasPrefix(prefix + " ") ? (id, name) : nil
                    }
                }.sorted { $0.1.count > $1.1.count }
                guard let match = matches.first else {
                    return .init(request: .init(mode: "help"), caption: "未识别画师。请用 /artist 数字ID [描述]，或 /artists 查看已配置名称。")
                }
                let longest = Set(matches.filter { $0.1.count == match.1.count }.map { $0.0 })
                guard longest.count == 1 else { return .init(request: .init(mode: "help"), caption: "有多位同名画师，请用 /artist 数字ID 指定。") }
                request.query = match.0
                let tail = String(input.dropFirst(match.1.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { request.prompt = tail }
            }
        }
        let filter = request.mode == "artist" ? (request.prompt ?? "") : request.query
        let qualitySearch = request.mode == "search"
        if qualitySearch && filter.isEmpty { return .init(request: request, caption: QQArtworkRequest.help) }
        let searching = (request.mode == "featured" || qualitySearch) && !filter.isEmpty
        let curated = request.mode != "hot" && !searching && filter.isEmpty
        var imageConfig = config
        if request.mode == "hot" { imageConfig.minLongEdge = 0; imageConfig.minShortEdge = 0 }
        let searchWord = Self.searchQuery(filter)
        let key = [scope, request.mode, request.query, filter, String(config.minLongEdge), String(config.minShortEdge), String(config.effectiveSearchMinBookmarks), config.pixivArtistIDs.joined(separator: ",")].joined(separator: "|")
        rejectedWorks = rejectedWorks.filter { Date().timeIntervalSince($0.value.0) < 1800 }
        if rejectedWorks[key] == nil, rejectedWorks.count >= 64, let oldest = rejectedWorks.min(by: { $0.value.0 < $1.value.0 })?.key { rejectedWorks.removeValue(forKey: oldest) }
        let scannedAt = rejectedWorks[key]?.0 ?? Date()
        var rejected = rejectedWorks[key]?.1 ?? []
        defer { rejectedWorks[key] = (scannedAt, Set(rejected.sorted().suffix(1000))) }
        var candidates: [(String, Int?, String?)] = []
        if request.mode == "featured", !searching { candidates = Self.featuredIDs.shuffled().map { ($0, nil, nil) } }
        else if !["featured", "search", "artist", "hot"].contains(request.mode) { return .init(request: request, caption: QQArtworkRequest.help) }
        let candidateLimit = qualitySearch ? 12 : 30
        var checked = 0, page = 1, date: String?
        repeat {
            var nextPage: Int?
            if searching || request.mode == "artist" {
                let artist = request.mode == "artist"
                var url = URLComponents(string: "https://www.pixiv.net")!
                if artist {
                    // The artist endpoint supports one tag; apply additional terms to this returned list, not individual detail requests.
                    let tag = searchWord.split(whereSeparator: { $0.isWhitespace }).first(where: { !$0.hasPrefix("-") }).map(String.init) ?? ""
                    url.path = "/ajax/user/\(request.query)/illusts/tag"
                    url.queryItems = [URLQueryItem(name: "tag", value: tag), .init(name: "offset", value: String((page - 1) * 30)), .init(name: "limit", value: "30"), .init(name: "lang", value: "zh")]
                } else {
                    url.path = "/ajax/search/illustrations/" + searchWord
                    url.queryItems = [URLQueryItem(name: "word", value: searchWord), .init(name: "order", value: "date_d"),
                        .init(name: "mode", value: "safe"), .init(name: "p", value: String(page)), .init(name: "s_mode", value: "s_tag"),
                        .init(name: "type", value: "illust"), .init(name: "ai_type", value: "1"), .init(name: "lang", value: "zh")]
                }
                let response = try await json(url.url!.absoluteString, beforeFetch: beforeFetch)
                guard response["error"] as? Bool == false, let body = response["body"] as? [String: Any],
                      let result = artist ? body : body["illust"] as? [String: Any],
                      let rows = result[artist ? "works" : "data"] as? [[String: Any]],
                      let total = result["total"] as? Int, total >= 0 else { throw AppFailure.message("Pixiv 搜索响应结构变化，本次未发送") }
                if !rows.isEmpty, page < 10, artist ? page * 30 < total : page < (result["lastPage"] as? Int ?? 1) { nextPage = page + 1 }
                // Source search already matched keywords. No second topic check for global results.
                var sourceRows = rows
                if qualitySearch, page == 1, let popular = body["popular"] as? [String: Any] {
                    // Public search recommendations are not the daily ranking or a complete popularity sort.
                    sourceRows = (popular["permanent"] as? [[String: Any]] ?? []) + (popular["recent"] as? [[String: Any]] ?? []) + rows
                }
                var seen = Set<String>()
                candidates = sourceRows.compactMap { row in
                    guard let id = QQPolicy.identifier(row["id"]), row["xRestrict"] as? Int == 0,
                          row["illustType"] as? Int == 0, let ai = row["aiType"] as? Int, ai != 2,
                          row["isMasked"] as? Bool != true, row["isUnlisted"] as? Bool == false,
                          let width = row["width"] as? Int, let height = row["height"] as? Int,
                          max(width, height) >= imageConfig.minLongEdge, min(width, height) >= imageConfig.minShortEdge,
                          !artist || QQPolicy.identifier(row["userId"]) == request.query,
                          seen.insert(id).inserted else { return nil }
                    let tags = row["tags"] as? [String] ?? []
                    guard !curated || (!Self.excludedTags(tags) && Self.animeGirl(tags: tags, artist: request.query, id: id)),
                          !artist || Self.matches(filter, in: tags + [row["title"] as? String ?? ""]) else { return nil }
                    return (id, nil, nil)
                }
                if randomArtist && filter.isEmpty { candidates.shuffle() }
            } else if request.mode == "hot" {
                let suffix = page == 1 ? "" : "&p=\(page)&date=\(date!)"
                let ranking = try await json("https://www.pixiv.net/ranking.php?mode=daily&content=illust&format=json" + suffix, beforeFetch: beforeFetch)
                guard let rows = ranking["contents"] as? [[String: Any]],
                      let currentDate = ranking["date"] as? String ?? (ranking["date"] as? Int).map(String.init),
                      currentDate.count == 8, currentDate.allSatisfy(\.isNumber), date == nil || date == currentDate else {
                    throw AppFailure.message("Pixiv 榜单结构或日期变化，本次未发送")
                }
                date = currentDate
                if let next = ranking["next"] as? Int, next == page + 1, next <= 10 { nextPage = next }
                candidates = rows.sorted { ($0["rank"] as? Int ?? Int.max) < ($1["rank"] as? Int ?? Int.max) }.compactMap { row in
                    guard let id = QQPolicy.identifier(row["illust_id"]), let type = row["illust_content_type"] as? [String: Any],
                          let rank = row["rank"] as? Int, (1...500).contains(rank),
                          (type["sexual"] as? Int ?? -1) == 0, type["lo"] as? Bool == false, type["grotesque"] as? Bool == false,
                          Self.matches(filter, in: (row["tags"] as? [String] ?? []) + [row["title"] as? String ?? ""]) else { return nil }
                    // No artist roster or sparse ranking-tag gender gate: validate complete work details below.
                    return (id, rank, currentDate)
                }
            }
            for (id, rank, workDate) in candidates where !rejected.contains(id) && !ledger.excludes(scope: scope, id: "pixiv:" + id, days: config.repeatDays) {
                guard checked < candidateLimit else {
                    return .init(request: request, caption: "本轮已检查 \(candidateLimit) 个候选，暂未找到合格新图。" + (qualitySearch ? "收藏门槛为 \(config.effectiveSearchMinBookmarks)，未降低标准。" : "") + "/next 继续向后筛选；带新关键词可调整条件。\n" + QQArtworkRequest.navigation)
                }
                checked += 1
                guard var work = try await detail(id, config: imageConfig, curated: curated, ranked: request.mode == "hot", beforeFetch: beforeFetch),
                      request.mode != "artist" || work.artistID == request.query,
                      request.mode != "featured" || searching || config.pixivArtistIDs.contains(work.artistID) else {
                    rejected.insert(id); continue
                }
                work.rank = rank; work.date = workDate
                if qualitySearch, work.bookmarks == nil || work.bookmarks! < config.effectiveSearchMinBookmarks {
                    rejected.insert(id); continue
                }
                if var ready = try await prepareWork(work, request: request, config: imageConfig, scope: scope, ledger: ledger, beforeFetch: beforeFetch) {
                    if searching { ready.caption = "Pixiv 关键词搜索：" + Self.clean(filter) + (qualitySearch ? "（收藏 ≥ \(config.effectiveSearchMinBookmarks)）" : "") + "\n" + ready.caption }
                    return ready
                }
                rejected.insert(id)
            }
            guard let nextPage else { break }; page = nextPage
        } while true
        if qualitySearch {
            return .init(request: request, caption: "本轮搜索候选中未找到收藏 ≥ \(config.effectiveSearchMinBookmarks)、画质达标且未发过的可用图片。未降低标准；可换关键词或在面板调整收藏门槛。/next 沿用当前搜索；不会用链接代替图片。\n" + QQArtworkRequest.navigation)
        }
        return .init(request: request, caption: request.mode == "hot"
            ? "本轮公开日榜暂未取得未发过的可用图片；不限制画师和题材。可用 /hot 新关键词 改筛选，或 /search 关键词 搜索全站。\n" + QQArtworkRequest.navigation
            : "本轮候选中未找到符合筛选、画质和去重条件的新图片。可调整关键词后重试；不会用链接代替图片。\n" + QQArtworkRequest.navigation)
    }
    private func prepareWork(_ work: Work, request: QQArtworkRequest, config: QQArtworkConfig, scope: String,
                             ledger: QQArtworkLedger, beforeFetch: () throws -> Void) async throws -> QQArtworkPrepared? {
        var downloaded = images[work.id]
        if downloaded == nil {
            for url in work.imageURLs {
                let bytes: Data
                do { bytes = try await fetch(url, limit: 20_000_000, beforeFetch: beforeFetch) }
                catch is ArtworkAssetMissing { continue }
                guard let image = try? Self.normalized(bytes, config: config) else { continue }
                downloaded = image; break
            }
            guard let image = downloaded else { return nil }
            images[work.id] = image; imageOrder.append(work.id)
            while imageOrder.count > 32 { images.removeValue(forKey: imageOrder.removeFirst()) }
        }
        guard let image = downloaded else { return nil }
        var caption = "【作品】\n《\(work.title)》\n画师：\(work.author)\n"
        if let date = work.date { caption += "Pixiv 日榜 \(date)" + (work.rank.map { " · 第 \($0) 名" } ?? "") + "\n" }
        if request.mode == "search" {
            caption += [work.bookmarks.map { "收藏 \($0)" }, work.likes.map { "点赞 \($0)" }, work.views.map { "浏览 \($0)" }].compactMap { $0 }.joined(separator: " · ") + "\n"
        }
        caption += "原帖：\(work.url)\n图片预览 · 已缩放，保留画面与水印。\n"
        caption += QQArtworkRequest.navigation
        if !work.artistID.isEmpty { caption += "\n• /artist \(work.artistID) [描述] → 同画师" }
        let result = QQArtworkPrepared(request: request, id: work.id, caption: caption, image: image)
        return ledger.excludes(scope: scope, id: work.id, hash: result.hash, days: config.repeatDays) ? nil : result
    }
    private func detail(_ id: String, config: QQArtworkConfig, curated: Bool, ranked: Bool, beforeFetch: () throws -> Void) async throws -> Work? {
        let data = try await json("https://www.pixiv.net/ajax/illust/\(id)", beforeFetch: beforeFetch)
        guard data["error"] as? Bool == false, let body = data["body"] as? [String: Any],
              QQPolicy.identifier(body["id"]) == id, body["xRestrict"] as? Int == 0, body["illustType"] as? Int == 0,
              let ai = body["aiType"] as? Int, ranked || ai != 2, body["isUnlisted"] as? Bool == false,
              let width = body["width"] as? Int, let height = body["height"] as? Int,
              max(width, height) >= config.minLongEdge, min(width, height) >= config.minShortEdge,
              let title = body["illustTitle"] as? String, !curated || Self.illustrationTitle(title), let author = body["userName"] as? String,
              let artist = QQPolicy.identifier(body["userId"]), let urls = body["urls"] as? [String: Any] else { return nil }
        let tags = ((body["tags"] as? [String: Any])?["tags"] as? [[String: Any]] ?? []).compactMap { $0["tag"] as? String }
        guard !curated || (!Self.excludedTags(tags) && Self.animeGirl(tags: tags, artist: artist, id: id)) else { return nil }
        var imageURLs: [String] = []
        for key in ["original", "regular"] {
            if let value = urls[key] as? String, Self.allowedURL(value) != nil, !imageURLs.contains(value) { imageURLs.append(value) }
        }
        guard !imageURLs.isEmpty else { return nil }
        return Work(id: "pixiv:" + id, title: Self.clean(title), author: Self.clean(author), artistID: artist,
                    url: "https://www.pixiv.net/artworks/" + id, imageURLs: imageURLs,
                    bookmarks: (body["bookmarkCount"] as? Int).flatMap { $0 >= 0 ? $0 : nil },
                    likes: (body["likeCount"] as? Int).flatMap { $0 >= 0 ? $0 : nil },
                    views: (body["viewCount"] as? Int).flatMap { $0 >= 0 ? $0 : nil })
    }
    static func clean(_ text: String) -> String {
        String(text.replacingOccurrences(of: #"[\r\n\x00-\x1f]|\[CQ:"#, with: " ", options: .regularExpression).prefix(100))
    }
    static func searchQuery(_ value: String) -> String {
        let translations = ["初音未来": "初音ミク", "白发": "白髪", "银发": "銀髪", "黑发": "黒髪", "蓝发": "青髪",
            "粉发": "ピンク髪", "金发": "金髪", "红发": "赤髪", "紫发": "紫髪", "长发": "ロングヘア",
            "短发": "ショートヘア", "双马尾": "ツインテール", "女仆": "メイド", "黑丝": "黒タイツ", "白丝": "白タイツ",
            "碧蓝档案": "ブルーアーカイブ", "蔚蓝档案": "ブルーアーカイブ", "星穹铁道": "スターレイル"]
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "(?:不要|排除|不含|不带)\\s*", with: " -", options: .regularExpression)
            .replacingOccurrences(of: "[，,、+]", with: " ", options: .regularExpression)
        for (word, tag) in translations.sorted(by: { $0.key.count > $1.key.count }) { text = text.replacingOccurrences(of: word, with: " " + tag + " ") }
        return text.replacingOccurrences(of: "-\\s+", with: "-", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func matches(_ query: String, in values: [String]) -> Bool {
        // Deterministic metadata filtering: each positive term is required, negatives are excluded.
        let groups = [
            ["初音未来", "初音ミク", "hatsune miku", "雪初音", "雪ミク"], ["原神", "genshin impact", "genshin"],
            ["崩坏星穹铁道", "星穹铁道", "スターレイル", "honkai star rail"], ["碧蓝档案", "蔚蓝档案", "ブルーアーカイブ", "ブルアカ", "blue archive"],
            ["白发", "白髪", "银发", "銀髪", "white hair", "silver hair"], ["黑发", "黒髪", "black hair"],
            ["蓝发", "青髪", "blue hair"], ["粉发", "ピンク髪", "pink hair"], ["金发", "金髪", "blonde hair", "blond hair"],
            ["红发", "赤髪", "red hair"], ["紫发", "紫髪", "purple hair"], ["长发", "ロングヘア", "long hair"],
            ["短发", "ショートヘア", "short hair"], ["双马尾", "ツインテール", "twintails"],
            ["猫耳", "ネコミミ", "ねこみみ", "cat ears"], ["狐耳", "きつね耳", "狐娘", "fox ears"],
            ["兽耳", "ケモミミ", "獣耳", "animal ears"], ["女仆", "メイド", "maid"], ["和服", "着物", "kimono"],
            ["黑丝", "黒タイツ", "black tights"], ["白丝", "白タイツ", "white tights"],
            ["美少女", "女の子", "girl", "girls", "少女"], ["动漫", "二次元", "anime"], ["游戏", "ゲーム", "game"]
        ]
        let generic: Set<String> = ["美少女", "动漫", "二次元", "游戏", "动漫美少女", "游戏美少女"]
        let cleaned = query.lowercased()
            .replacingOccurrences(of: "(?:请帮我|帮我|给我|来一张|来点|找一张|我想看|想看|我要|看看|一张)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?:不要|排除|不含|不带)\\s*", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "(?:并且|以及|的|和|[，,、+])", with: " ", options: .regularExpression)
        let aliases = groups.flatMap { $0 }.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let expression = try! NSRegularExpression(pattern: "-?(?:" + aliases + ")|[^\\s]+")
        let tokens = expression.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)).compactMap { Range($0.range, in: cleaned).map { String(cleaned[$0]) } }
        let joined = values.joined(separator: " ").lowercased()
        return tokens.allSatisfy { token in
            let negative = token.hasPrefix("-"), word = token.hasPrefix("-") ? String(token.dropFirst()) : token
            guard !word.isEmpty else { return false }
            if !negative && generic.contains(word) { return true }
            let found = (groups.first { $0.contains(word) } ?? [word]).contains { joined.contains($0) }
            return negative ? !found : found
        }
    }
    static func illustrationTitle(_ title: String) -> Bool {
        title.range(of: "(?i)(お品書き|新刊|宣伝|サンプル|通販|委託|sample|告知)", options: .regularExpression) == nil
    }
    static func excludedTags(_ tags: [String]) -> Bool {
        tags.contains { $0.range(of: #"(?i)(r-?18|nsfw|裸|エロ|露出|乳首|下着|パンツ|水着|ロリ|ショタ|ビキニ|おっぱい|男の子|男性|boy|gore|guro|リョナ|性器)"#, options: .regularExpression) != nil }
    }
    static func allowedURL(_ value: String) -> URL? {
        guard let u = URL(string: value), u.scheme == "https", u.user == nil, u.password == nil, u.port == nil else { return nil }
        if u.host == "www.pixiv.net", u.path == "/ranking.php" || u.path.hasPrefix("/ajax/illust/") || u.path.hasPrefix("/ajax/user/") || u.path.hasPrefix("/ajax/search/illustrations/") { return u }
        if u.host == "i.pximg.net", (u.path.hasPrefix("/img-original/") || u.path.hasPrefix("/img-master/")) { return u }
        return nil
    }
    private func json(_ value: String, beforeFetch: () throws -> Void) async throws -> [String: Any] {
        if let cached = cache[value], Date().timeIntervalSince(cached.0) < 1800 { try Task.checkCancellation(); return cached.1 }
        let bytes = try await fetch(value, limit: 3_000_000, beforeFetch: beforeFetch)
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw AppFailure.message("插画来源响应结构无效") }
        if cache.count >= 100 { cache.removeValue(forKey: cache.min(by: { $0.value.0 < $1.value.0 })!.key) }
        cache[value] = (Date(), object); return object
    }
    private func fetch(_ value: String, limit: Int, beforeFetch: () throws -> Void) async throws -> Data {
        guard let url = Self.allowedURL(value) else { throw AppFailure.message("插画下载地址不受支持") }
        let host = url.host!
        guard blockedUntil[host].map({ $0 <= Date() }) ?? true else { throw AppFailure.message("插画来源限流冷却中，请稍后再试") }
        let wait = spacing - Date().timeIntervalSince(lastFetch)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        try beforeFetch(); lastFetch = Date()
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if host.hasSuffix("pixiv.net") || host == "i.pximg.net" { request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer") }
        // Download chunks to a temporary file off the main actor, instead of resuming Swift once per byte.
        let delegate = ArtworkDownloadGuard(limit: limit)
        let file: URL, response: URLResponse
        do { (file, response) = try await session.download(for: request, delegate: delegate) }
        catch {
            if delegate.exceeded { throw AppFailure.message("插画响应过大，已停止") }
            throw error
        }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse else { throw AppFailure.message("插画来源无有效响应") }
        if [403, 429].contains(http.statusCode) {
            blockedUntil[host] = Date().addingTimeInterval(min(3600, max(60, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 300)))
        }
        if host == "i.pximg.net", [404, 410].contains(http.statusCode) { throw ArtworkAssetMissing() }
        guard http.statusCode == 200, response.expectedContentLength <= limit else { throw AppFailure.message("插画来源暂不可用（HTTP \(http.statusCode)），未绕过限制或自动重试") }
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit else { throw AppFailure.message("插画响应过大，已停止") }
        try Task.checkCancellation()
        return try Data(contentsOf: file)
    }
    static func normalized(_ data: Data, config: QQArtworkConfig) throws -> Data {
        #if os(Linux)
        return try LinuxImages.process(data, mode: "artwork", options: ["minLongEdge": config.minLongEdge, "minShortEdge": config.minShortEdge])[0]
        #else
        guard data.count <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              (1...12000).contains(width), (1...12000).contains(height), width * height <= 40_000_000,
              max(width, height) >= config.minLongEdge, min(width, height) >= config.minShortEdge,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) else { throw AppFailure.message("插画格式或清晰度不符合要求") }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw AppFailure.message("插画编码失败") }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(dest), output.length <= 3_000_000 else { throw AppFailure.message("插画压缩失败") }
        return output as Data
        #endif
    }
    // Selected and visually checked anime/game female character works; all still pass current detail filters.
    nonisolated static let featuredIDs = ["53325959", "50533824", "49590533", "73164819", "29118503", "28260838"]
    static func animeGirl(tags: [String], artist: String, id: String) -> Bool {
        let joined = tags.joined(separator: " ")
        guard joined.range(of: #"(?i)(実写|写真|コスプレ|cosplay|photograph|男の子|男性|男主|boys?|風景のみ|landscape.only)"#, options: .regularExpression) == nil else { return false }
        if featuredIDs.contains(id) { return true } // Human-reviewed subject/style, not inferred from character gender.
        let female = joined.range(of: #"(?i)(女の子|少女|girls?|女性|初音ミク|博麗霊夢|霧雨魔理沙|ウマ娘)"#, options: .regularExpression) != nil
        let theme = joined.range(of: #"(?i)(アニメ|anime|manga|オリジナル|二次元|美少女|ゲーム|game|原神|genshin|崩壊|崩坏|スターレイル|アークナイツ|明日方舟|ブルーアーカイブ|碧蓝档案|ブルアカ|アズールレーン|碧蓝航线|東方|Fate|FGO|初音ミク|VOCALOID|ウマ娘|リゼロ|アイドルマスター)"#, options: .regularExpression) != nil || artists.contains { $0.id == artist }
        return female && theme
    }

}
private struct ArtworkAssetMissing: Error {}

private final class ArtworkDownloadGuard: NSObject, URLSessionDownloadDelegate {
    private let limit: Int64
    private let lock = NSLock()
    private var overLimit = false
    var exceeded: Bool { lock.lock(); defer { lock.unlock() }; return overLimit }
    init(limit: Int) { self.limit = Int64(limit) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
            lock.lock(); overLimit = true; lock.unlock(); downloadTask.cancel()
        }
    }
}
