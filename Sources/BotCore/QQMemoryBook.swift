import Foundation
import CryptoKit

public struct QQMemoryOptions: Codable, Equatable, Sendable {
    public var messageThreshold = 20
    public var characterThreshold = 6000
    public var intervalMinutes = 10
    public var retrievalCharacters = 1800
    public init() {}
    public func validate() throws {
        guard (4...100).contains(messageThreshold), (1000...20000).contains(characterThreshold),
              (1...120).contains(intervalMinutes), (600...4000).contains(retrievalCharacters) else {
            throw CoreError.invalid("记忆整理范围：4–100 条、1000–20000 字符、1–120 分钟；检索预算 600–4000 字符")
        }
    }
}

public struct QQMemoryEvent: Codable, Equatable, Sendable {
    public let id: String
    public let subject: String
    public let text: String
    public let at: Date
    public init(id: String, subject: String, text: String, at: Date) {
        self.id = id; self.subject = subject; self.text = String(QQMemoryBook.redact(text).prefix(1200)); self.at = at
    }
}

public struct QQMemoryItem: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID().uuidString
    public let subject: String
    public let kind: String
    public let text: String
    public let keywords: [String]
    public let importance: Int
    public let sourceIDs: [String]
    public let updatedAt: Date
    public let expiresAt: Date
    public var invalidatedAt: Date?
    public func current(_ now: Date) -> Bool { invalidatedAt == nil && expiresAt > now }
}

public struct QQMemoryDelta: Decodable, Sendable {
    public struct Change: Decodable, Sendable {
        public let operation: String
        public let replaces: [String]
        public let subject: String
        public let kind: String
        public let text: String
        public let keywords: [String]
        public let importance: Int
        public let sourceID: String
        public let evidence: String
        public let days: Int
    }
    public let summary: String
    public let changes: [Change]
    public static func decode(_ raw: String) throws -> Self {
        guard raw.utf8.count <= 24000 else { throw CoreError.invalid("记忆整理输出过长") }
        let data = Data(raw.utf8)
        guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(fields.keys) == ["summary", "changes"] else {
            throw CoreError.invalid("记忆整理字段无效")
        }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.summary.count <= 400, result.changes.count <= 12 else { throw CoreError.invalid("记忆整理超出条目预算") }
        return result
    }
}

/// One account + one private peer/group. Pending excerpts survive pause; no cross-scope search.
public struct QQMemoryBook: Codable, Equatable, Sendable {
    public private(set) var pending: [QQMemoryEvent] = []
    public private(set) var recent: [QQMemoryEvent] = []
    public private(set) var items: [QQMemoryItem] = []
    public private(set) var knownIDs: [String] = []
    public private(set) var lastCompactedAt: Date?
    public private(set) var droppedEvents = 0
    public init() {}
    public static func subject(account: String, target: String, sender: String) -> String {
        if sender == account { return "OWNER" }
        if target.hasPrefix("private:") { return "PEER" }
        let digest = SHA256.hash(data: Data((account + ":" + target + ":" + sender).utf8))
        return "MEMBER_" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
    public static func redact(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)(sk-[a-z0-9_-]+|cfut_[a-z0-9_-]+|bearer\s+[a-z0-9._-]+|(?:密码|口令|密钥|token|api.?key)\s*[:：=]\s*[^\s，。；;]+|https?://[^\s]+[?][^\s]+)"#, with: "[敏感信息省略]", options: .regularExpression)
    }
    @discardableResult public mutating func append(_ event: QQMemoryEvent) -> Bool {
        guard !event.text.isEmpty, !knownIDs.contains(event.id) else { return false }
        knownIDs.append(event.id); knownIDs = Array(knownIDs.suffix(1024))
        recent.append(event); recent = Array(recent.sorted { $0.at < $1.at }.suffix(24))
        if !["BOT", "SELF_UNKNOWN"].contains(event.subject) {
            pending.append(event); pending.sort { $0.at < $1.at }
            if pending.count > 128 { droppedEvents += pending.count - 128; pending = Array(pending.suffix(128)) }
        }
        return true
    }
    public func due(options: QQMemoryOptions, now: Date = Date()) -> Bool {
        guard let oldest = pending.first else { return false }
        return pending.count >= options.messageThreshold || pending.reduce(0, { $0 + $1.text.count }) >= options.characterThreshold || now.timeIntervalSince(oldest.at) >= Double(options.intervalMinutes * 60)
    }
    public func batch() -> [QQMemoryEvent] {
        var result: [QQMemoryEvent] = [], size = 0
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        for event in pending.prefix(32) {
            guard let data = try? encoder.encode(event) else { break }
            let cost = String(decoding: data, as: UTF8.self).count + 1
            if size + cost > 7500 { break }
            result.append(event); size += cost
        }
        return result
    }
    /// Validate every mutation against supplied evidence and candidates, then apply atomically.
    public mutating func apply(_ delta: QQMemoryDelta, batch: [QQMemoryEvent], candidateIDs: Set<String>, now: Date = Date()) throws {
        let sources = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
        guard !batch.isEmpty, Set(sources.keys).isSubset(of: Set(pending.map(\.id))) else { throw CoreError.invalid("记忆批次已变化") }
        let allowedKinds = ["preference", "fact", "task", "event"]
        let changes = delta.changes
        for item in changes {
            guard ["upsert", "forget"].contains(item.operation), allowedKinds.contains(item.kind),
                  let source = sources[item.sourceID], source.subject == item.subject,
                  !item.evidence.isEmpty, item.evidence.count <= 200, source.text.contains(item.evidence),
                  item.replaces.count <= 6, Set(item.replaces).isSubset(of: candidateIDs),
                  item.replaces.allSatisfy({ id in items.contains { $0.id == id && $0.subject == item.subject && $0.current(now) } }),
                  item.text.count <= 180, item.keywords.count <= 6, item.keywords.allSatisfy({ !$0.isEmpty && $0.count <= 20 }),
                  (1...3).contains(item.importance), (1...365).contains(item.days),
                  (item.operation == "forget" ? !item.replaces.isEmpty && item.text.isEmpty : !item.text.isEmpty) else {
                throw CoreError.invalid("记忆证据、归属或更新范围未通过校验")
            }
        }
        // The whole delta has passed; old versions remain marked as historical.
        for change in changes {
            let obsoleteSources = Set(items.filter { change.replaces.contains($0.id) }.flatMap(\.sourceIDs))
            for i in items.indices where change.replaces.contains(items[i].id) || (items[i].kind == "episode" && !obsoleteSources.isDisjoint(with: items[i].sourceIDs)) { items[i].invalidatedAt = now }
            guard change.operation == "upsert" else { continue }
            let text = Self.redact(change.text)
            if items.contains(where: { $0.subject == change.subject && $0.text == text && $0.current(now) }) { continue }
            let days = min(change.days, change.kind == "event" ? 90 : change.kind == "task" ? 30 : 365)
            items.append(QQMemoryItem(subject: change.subject, kind: change.kind, text: text, keywords: change.keywords.map(Self.redact), importance: change.importance, sourceIDs: [change.sourceID], updatedAt: now, expiresAt: now.addingTimeInterval(Double(days * 86400))))
        }
        if !delta.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(QQMemoryItem(subject: "CONVERSATION", kind: "episode", text: Self.redact(delta.summary), keywords: [], importance: 1, sourceIDs: batch.map(\.id), updatedAt: now, expiresAt: now.addingTimeInterval(90 * 86400)))
        }
        let active = items.filter { $0.kind != "episode" && $0.current(now) }.sorted { ($0.importance, $0.updatedAt) > ($1.importance, $1.updatedAt) }.prefix(256)
        let historical = items.filter { !$0.current(now) && now.timeIntervalSince($0.invalidatedAt ?? $0.expiresAt) < 90 * 86400 }.suffix(64)
        let episodes = items.filter { $0.kind == "episode" && $0.current(now) }.suffix(64)
        items = Array(active) + historical + episodes
        pending.removeAll { sources[$0.id] != nil }; lastCompactedAt = now
    }
    public mutating func importLegacy(text: String, subject: String, at: Date) {
        let characters = Array(Self.redact(text).prefix(2000))
        for offset in stride(from: 0, to: characters.count, by: 600) {
            let fragment = String(characters[offset..<min(offset + 600, characters.count)])
            items.append(QQMemoryItem(subject: subject, kind: "legacy", text: fragment, keywords: [], importance: 1, sourceIDs: [], updatedAt: at, expiresAt: at.addingTimeInterval(90 * 86400)))
        }
    }
}

/// Inverted lexical index: rebuilt only on compaction/migration, never calls an embedding service.
public struct QQMemoryIndex: Sendable {
    private let records: [String: QQMemoryItem]
    private var postings: [String: Set<String>] = [:]
    public init(_ items: [QQMemoryItem]) {
        records = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in items {
            for term in Self.terms(item.text + " " + item.keywords.joined(separator: " ")) { postings[term, default: []].insert(item.id) }
        }
    }
    private static func terms(_ text: String) -> Set<String> {
        let scalars = Array(text.lowercased().unicodeScalars)
        var words = Set<String>(), word = "", chinese: Unicode.Scalar?
        for c in scalars.prefix(12000) {
            if (0x3400...0x9fff).contains(c.value) {
                if !word.isEmpty { words.insert(word); word = "" }
                if let previous = chinese { words.insert(String(previous) + String(c)) }
                chinese = c
            } else {
                chinese = nil
                if CharacterSet.alphanumerics.contains(c) { word.unicodeScalars.append(c) }
                else if !word.isEmpty { words.insert(word); word = "" }
            }
        }
        if !word.isEmpty { words.insert(word) }; return words
    }
    public func search(_ query: String, subject: String, limit: Int = 12, now: Date = Date(), history: Bool = false) -> [QQMemoryItem] {
        var scores: [String: Double] = [:]
        for term in Self.terms(query) {
            let matches = postings[term] ?? []
            let weight = log(1 + Double(records.count + 1) / Double(matches.count + 1))
            for id in matches { scores[id, default: 0] += weight }
        }
        // Small persistent context: current speaker's profile and open tasks, even without word overlap.
        for item in records.values where item.subject == subject && ["preference", "task", "legacy"].contains(item.kind) { scores[item.id, default: 0] += 1 }
        return scores.compactMap { id, score -> (QQMemoryItem, Double)? in
            guard let item = records[id], item.current(now) || (history && now.timeIntervalSince(item.invalidatedAt ?? item.expiresAt) < 90 * 86400) else { return nil }
            let freshness = 1 / (1 + max(0, now.timeIntervalSince(item.updatedAt)) / 86400)
            return (item, score + Double(item.importance) * 0.15 + freshness * 0.3 + (item.subject == subject ? 0.5 : 0))
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
    public func context(_ query: String, subject: String, characters: Int, now: Date = Date()) -> String {
        let historical = ["以前", "过去", "之前", "曾经", "改前"].contains { query.contains($0) }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
        var lines: [String] = [], count = 0
        for item in search(query, subject: subject, now: now, history: historical) {
            let state = !item.current(now) ? "历史/已失效，不能当作现在" : item.kind == "legacy" ? "旧摘要/未经逐条核验" : item.kind == "episode" ? "历史片段/当时状态" : "已记录"
            let line = "[\(item.subject)·\(item.kind)·\(formatter.string(from: item.updatedAt))·\(state)] \(item.text)"
            if count + line.count + 1 > characters { continue }
            lines.append(line); count += line.count + 1
        }
        return lines.joined(separator: "\n")
    }
}
