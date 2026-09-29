import Foundation

public struct QQArtworkConfig: Codable, Equatable, Sendable {
    public var enabled = false
    public var agentEnabled = true
    public var dailyPerChat = 20
    public var networkDailyLimit = 300
    public var minLongEdge = 1400
    public var minShortEdge = 720
    public var repeatDays = 30
    public var searchMinBookmarks: Int?
    public var effectiveSearchMinBookmarks: Int {
        get { searchMinBookmarks ?? 1000 }
        set { searchMinBookmarks = newValue }
    }
    public var pixivArtistIDs = ["688570", "212801", "17429", "1039353", "1554775", "27517"]
    // Optional for compatibility with configurations saved before artist management.
    public var artistNames: [String: String]?
    // Legacy operator-supplied evidence retained for compatibility; no longer gates public-image retrieval.
    public var imagePermissions: [String: String] = ["688570": "https://www.pixiv.net/users/688570"]
    public var scheduleEnabled = false
    public var scheduleTargets: [String] = []
    public var scheduleHour = 19
    public var scheduleMinute = 0
    public var scheduleTimeZone = "Asia/Shanghai"
    public var scheduleMode = "hot"
    public var scheduleFrequency: String?
    public var effectiveScheduleFrequency: String { scheduleFrequency ?? "daily" }
    public init() {}
    public func validate() throws {
        guard (1...1000).contains(dailyPerChat), (10...2000).contains(networkDailyLimit),
              (0...4096).contains(minLongEdge), (0...4096).contains(minShortEdge), minLongEdge >= minShortEdge,
              (1...90).contains(repeatDays), (1...1_000_000).contains(effectiveSearchMinBookmarks), pixivArtistIDs.count <= 20,
              Set(pixivArtistIDs).count == pixivArtistIDs.count, pixivArtistIDs.allSatisfy(QQConfig.validID),
              (artistNames ?? [:]).count <= 20, (artistNames ?? [:]).allSatisfy({ pixivArtistIDs.contains($0.key) && !$0.value.isEmpty && $0.value.count <= 80 && !$0.value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }),
              imagePermissions.count <= 20, imagePermissions.allSatisfy({ QQConfig.validID($0.key) && Self.evidenceURL($0.value) }),
              (0...23).contains(scheduleHour), (0...59).contains(scheduleMinute), TimeZone(identifier: scheduleTimeZone) != nil,
              ["hot", "featured"].contains(scheduleMode), ["daily", "hourly"].contains(effectiveScheduleFrequency), scheduleTargets.count <= 20,
              Set(scheduleTargets).count == scheduleTargets.count,
              scheduleTargets.allSatisfy({ key in let p = key.split(separator: ":"); return p.count == 2 && ["private", "group"].contains(String(p[0])) && QQConfig.validID(String(p[1])) }) else {
            throw CoreError.invalid("插画配置无效：检查尺寸、收藏门槛（1–1000000）、额度、画师 ID、许可链接或定时时间与目标")
        }
    }
    public static func artistID(from input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if QQConfig.validID(value) { return value }
        guard value.count <= 500, let url = URL(string: value), url.scheme == "https",
              ["www.pixiv.net", "pixiv.net"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.port == nil else {
            throw CoreError.invalid("请输入 Pixiv 画师数字 ID 或 https://www.pixiv.net/users/ID 主页链接")
        }
        var parts = url.path.split(separator: "/").map(String.init)
        if parts.count == 3, ["en", "zh", "zh-tw", "ja", "ko"].contains(parts[0]) { parts.removeFirst() }
        guard parts.count == 2, parts[0] == "users", QQConfig.validID(parts[1]) else {
            throw CoreError.invalid("需要画师主页链接，不能使用作品链接")
        }
        return parts[1]
    }
    public static func evidenceURL(_ value: String) -> Bool {
        guard value.count <= 1000, let u = URL(string: value), u.scheme == "https", let host = u.host,
              host.contains("."), u.user == nil, u.password == nil, u.port == nil else { return false }
        return true // Stored evidence only; never fetched by the downloader.
    }
    public func dueDate(now: Date, since: Date) -> Date? {
        guard enabled, scheduleEnabled, let zone = TimeZone(identifier: scheduleTimeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let candidate: Date?
        if effectiveScheduleFrequency == "hourly", let start = calendar.dateInterval(of: .hour, for: now)?.start {
            candidate = calendar.date(byAdding: .minute, value: scheduleMinute, to: start)
        } else { candidate = calendar.date(bySettingHour: scheduleHour, minute: scheduleMinute, second: 0, of: now) }
        guard let due = candidate,
              due >= since, now >= due, now.timeIntervalSince(due) < 60 else { return nil }
        return due
    }
    public func scheduleKey(account: String, target: String, due: Date) -> String {
        // Hourly slots use the absolute hour, keeping repeated DST hours distinct.
        if effectiveScheduleFrequency == "hourly" {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: scheduleTimeZone) ?? .current
            let hour = c.dateInterval(of: .hour, for: due)!.start
            return "\(account):\(target):hour:\(Int64(hour.timeIntervalSince1970))"
        }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: scheduleTimeZone) ?? .current
        let p = c.dateComponents([.year, .month, .day], from: due)
        return "\(account):\(target):\(p.year!)-\(p.month!)-\(p.day!)"
    }
}

public struct QQArtworkRequest: Codable, Equatable, Sendable {
    public var mode: String
    public var query: String
    public var prompt: String?
    public init(mode: String, query: String = "", prompt: String? = nil) { self.mode = mode; self.query = query; self.prompt = prompt }
    public static let navigation = "────────\n【继续操作】\n• /next [新关键词] → 下一张\n• /search 关键词或作品ID → 搜图\n• /hot [关键词] → 日榜\n• /persona → 会话性格\n• /search help → 完整用法"
    public static let help = """
    【插画命令】
    不调用大模型 · 仅已启用会话可用
    ────────
    01｜统一搜图
    /search 关键词
    优先收藏达标作品；本轮无达标图时按真实热度选保底图，并注明降级。

    02｜作品直查
    /search 作品ID或Pixiv作品链接
    /id 作品ID
    直接查询指定作品，不要求收藏门槛；仍检查图片可用性、画质与去重。

    03｜每日榜单
    /hot [关键词]
    从第1名按序取图，不限画师与题材；填写关键词则在榜内筛选。

    04｜继续看图
    /next [新关键词]
    沿用上次搜索或榜单；填写新关键词则替换条件。
    ID查询没有下一张，可用 /next 新关键词 开始搜索。
    ────────
    【输入示例】
    • /search 白发 猫耳 -黑丝
    • /search https://www.pixiv.net/artworks/53325959

    【小提示】
    • /art 是 /search 的兼容别名，无需选择两个入口。
    • /artist 与 /artists 已退役；发图仍附画师署名。
    • 支持常见标签译名、多关键词和 -词 排除。
    • 收藏是热度参考；保底只放宽热度，不保证总有结果。
    • /search help → 再看帮助
    """
    /// Parse an identifier into a canonical Pixiv work ID; never fetch user-supplied URLs.
    public static func artworkID(_ input: String) -> String? {
        if QQConfig.validID(input) { return input }
        guard input.count <= 500, let url = URL(string: input), url.scheme == "https",
              ["www.pixiv.net", "pixiv.net"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        var parts = url.path.split(separator: "/").map(String.init)
        if parts.count == 3, ["en", "zh", "zh-tw", "ja", "ko"].contains(parts[0]) { parts.removeFirst() }
        guard parts.count == 2, parts[0] == "artworks", QQConfig.validID(parts[1]) else { return nil }
        return parts[1]
    }
    public static func parse(_ text: String) -> Self? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = value.range(of: #"^/(artists|artist|search|next|hot|art|id)(?=$|\s|[\x{3400}-\x{9fff}])"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let verb = String(value[range]).lowercased()
        let query = String(value[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count <= 500, !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), !query.contains("[CQ:") else { return Self(mode: "help") }
        if ["/artist", "/artists"].contains(verb) { return Self(mode: "retiredArtist") }
        if ["help", "帮助", "?"].contains(query.lowercased()) { return Self(mode: "help") }
        if ["/search", "/art", "/id"].contains(verb) {
            if let id = artworkID(query) { return Self(mode: "id", query: id) }
            guard verb != "/id", !query.isEmpty, !query.allSatisfy(\.isNumber), !query.contains("://"), query.count <= 80 else { return Self(mode: "help") }
            return Self(mode: "search", query: query)
        }
        guard query.count <= 80, !query.contains("://") else { return Self(mode: "help") }
        return Self(mode: verb == "/hot" ? "hot" : "next", query: query)
    }
}

public struct QQArtworkDelivery: Codable, Sendable {
    public var ticket: UUID
    public var scope: String
    public var artworkID: String
    public var hash: String?
    public var at: Date
    public var state: String
}
public struct QQArtworkLedger: Codable, Sendable {
    public var deliveries: [QQArtworkDelivery] = []
    public var continuation: [String: QQArtworkRequest] = [:]
    public var schedules: [String: Date] = [:]
    public var networkDay = ""
    public var networkCalls = 0
    public init() {}
    public func excludes(scope: String, id: String, hash: String? = nil, days: Int, now: Date = Date()) -> Bool {
        deliveries.contains { $0.scope == scope && now.timeIntervalSince($0.at) < Double(days * 86400) &&
            ($0.artworkID == id || (hash != nil && $0.hash == hash)) }
    }
    public func allowed(scope: String, limit: Int, now: Date = Date()) -> Bool {
        deliveries.filter { $0.scope == scope && Calendar.current.isDate($0.at, inSameDayAs: now) }.count < limit
    }
    public mutating func reserve(ticket: UUID, scope: String, id: String, hash: String?, request: QQArtworkRequest, now: Date = Date()) {
        deliveries.append(QQArtworkDelivery(ticket: ticket, scope: scope, artworkID: id, hash: hash, at: now, state: "sending"))
        continuation[scope] = request
        trim(now: now)
    }
    public mutating func finish(_ ticket: UUID, confirmed: Bool) {
        if let index = deliveries.firstIndex(where: { $0.ticket == ticket }) { deliveries[index].state = confirmed ? "confirmed" : "unknown" }
    }
    public mutating func recover() {
        for index in deliveries.indices where deliveries[index].state == "sending" { deliveries[index].state = "unknown" }
        trim()
    }
    public mutating func reserveNetwork(limit: Int, now: Date = Date()) throws {
        let day = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: now))
        if networkDay != day { networkDay = day; networkCalls = 0 }
        guard networkCalls < limit else { throw CoreError.invalid("今日插画来源请求额度已用完，未调用模型") }
        networkCalls += 1
    }
    public mutating func trim(now: Date = Date()) {
        deliveries = Array(deliveries.filter { now.timeIntervalSince($0.at) < 90 * 86400 }.suffix(20000))
        schedules = schedules.filter { now.timeIntervalSince($0.value) < 90 * 86400 }
        // An empty result still establishes a search intent for /next; no delivery is required.
        if continuation.count > 100 {
            continuation = Dictionary(uniqueKeysWithValues: continuation.sorted { $0.key < $1.key }.prefix(100).map { ($0.key, $0.value) })
        }
    }
}
