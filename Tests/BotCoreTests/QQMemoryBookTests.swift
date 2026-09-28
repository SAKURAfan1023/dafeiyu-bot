import Foundation
import Testing
@testable import BotCore

struct QQMemoryBookTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func delta(source: QQMemoryEvent, text: String = "喜欢清淡的晚饭", replaces: [String] = [], operation: String = "upsert", subject: String? = nil, evidence: String? = nil) throws -> QQMemoryDelta {
        let data = try JSONSerialization.data(withJSONObject: ["summary": "", "changes": [["operation": operation, "replaces": replaces, "subject": subject ?? source.subject, "kind": "preference", "text": text, "keywords": ["晚饭", "饮食", "口味"], "importance": 3, "sourceID": source.id, "evidence": evidence ?? source.text, "days": 365]]])
        return try QQMemoryDelta.decode(String(decoding: data, as: UTF8.self))
    }
    @Test func timeCountAndLengthRotateAndPendingSurvivesReload() throws {
        var options = QQMemoryOptions(); options.messageThreshold = 4; options.characterThreshold = 1000; options.intervalMinutes = 1
        var book = QQMemoryBook()
        let e = QQMemoryEvent(id: "1", subject: "PEER", text: "我喜欢清淡的晚饭", at: now)
        let added = book.append(e), duplicate = book.append(e); #expect(added); #expect(!duplicate); #expect(!book.due(options: options, now: now))
        #expect(book.due(options: options, now: now.addingTimeInterval(61)))
        let loaded = try JSONDecoder().decode(QQMemoryBook.self, from: JSONEncoder().encode(book))
        #expect(loaded.pending == [e]); #expect(loaded.knownIDs == ["1"])
        for n in 2...4 { book.append(QQMemoryEvent(id: "\(n)", subject: "PEER", text: "普通问候", at: now)) }
        #expect(book.due(options: options, now: now))
        var long = QQMemoryBook(); long.append(QQMemoryEvent(id: "5", subject: "PEER", text: String(repeating: "长", count: 1001), at: now))
        #expect(long.due(options: options, now: now))
        try book.apply(try .decode(#"{"summary":"","changes":[]}"#), batch: book.batch(), candidateIDs: [], now: now)
        #expect(book.pending.isEmpty); let repeated = book.append(e); #expect(!repeated); #expect(book.recent.count == 4)
    }
    @Test func correctionKeepsHistoryAndRejectsWrongSpeakerOrFabricatedEvidence() throws {
        var book = QQMemoryBook()
        let original = QQMemoryEvent(id: "1", subject: "PEER", text: "我喜欢清淡的晚饭", at: now)
        book.append(original); try book.apply(delta(source: original), batch: [original], candidateIDs: [], now: now)
        let first = try #require(book.items.first)
        let correction = QQMemoryEvent(id: "2", subject: "PEER", text: "我改口了，现在晚饭喜欢吃辣", at: now.addingTimeInterval(10))
        book.append(correction)
        let before = book
        #expect(throws: (any Error).self) { try book.apply(delta(source: correction, subject: "OWNER"), batch: [correction], candidateIDs: [first.id], now: now) }
        #expect(throws: (any Error).self) { try book.apply(delta(source: correction, evidence: "没有说过的内容"), batch: [correction], candidateIDs: [first.id], now: now) }
        #expect(throws: (any Error).self) { try book.apply(delta(source: correction, replaces: [first.id]), batch: [correction], candidateIDs: [], now: now) }
        #expect(book == before)
        try book.apply(delta(source: correction, text: "现在晚饭喜欢吃辣", replaces: [first.id]), batch: [correction], candidateIDs: [first.id], now: now.addingTimeInterval(10))
        let index = QQMemoryIndex(book.items)
        let current = index.context("晚饭口味", subject: "PEER", characters: 500, now: now.addingTimeInterval(20))
        #expect(current.contains("现在晚饭喜欢吃辣")); #expect(!current.contains("清淡"))
        let history = index.context("以前的晚饭口味", subject: "PEER", characters: 600, now: now.addingTimeInterval(20))
        #expect(history.contains("历史/已失效")); #expect(history.contains("清淡"))
        #expect(current.count <= 500)
        let forget = QQMemoryEvent(id: "3", subject: "PEER", text: "撤销我刚才的晚饭喜好记录", at: now.addingTimeInterval(30))
        book.append(forget); let latest = try #require(book.items.first { $0.current(now.addingTimeInterval(30)) })
        try book.apply(delta(source: forget, text: "", replaces: [latest.id], operation: "forget"), batch: [forget], candidateIDs: [latest.id], now: now.addingTimeInterval(30))
        #expect(QQMemoryIndex(book.items).search("晚饭", subject: "PEER", now: now.addingTimeInterval(31)).isEmpty)
    }
    @Test func isolatedSubjectsSecretRedactionAndBoundedJournal() throws {
        let member = QQMemoryBook.subject(account: "12345", target: "group:99999", sender: "54321")
        #expect(member != QQMemoryBook.subject(account: "12345", target: "group:88888", sender: "54321"))
        #expect(!member.contains("54321")); #expect(QQMemoryBook.subject(account: "12345", target: "group:99999", sender: "12345") == "OWNER")
        var a = QQMemoryBook(), b = QQMemoryBook()
        let event = QQMemoryEvent(id: "1", subject: member, text: "喜欢清淡的晚饭", at: now)
        a.append(event); try a.apply(delta(source: event), batch: [event], candidateIDs: [], now: now)
        #expect(QQMemoryIndex(b.items).search("晚饭", subject: member, now: now).isEmpty)
        b.append(QQMemoryEvent(id: "secret", subject: "PEER", text: "API key: sk-syntheticsecret token: cfut_syntheticsecret", at: now))
        #expect(!String(decoding: try JSONEncoder().encode(b), as: UTF8.self).contains("syntheticsecret"))
        b.append(QQMemoryEvent(id: "bot", subject: "BOT", text: "BOT 猜测", at: now))
        #expect(b.pending.count == 1)
        for i in 0..<140 { b.append(QQMemoryEvent(id: "bulk\(i)", subject: "PEER", text: "合成消息", at: now)) }
        #expect(b.pending.count == 128); #expect(b.recent.count == 24); #expect(b.droppedEvents == 13)
    }
    @Test func retrievalBenchmarkAndExpiration() throws {
        var book = QQMemoryBook()
        for i in 0..<256 {
            let event = QQMemoryEvent(id: "\(i)", subject: "MEMBER_\(i)", text: "第\(i)位成员喜欢清淡晚饭", at: now)
            book.append(event); try book.apply(delta(source: event, text: event.text), batch: [event], candidateIDs: [], now: now)
        }
        let index = QQMemoryIndex(book.items), start = Date()
        for _ in 0..<200 { #expect(!index.search("晚饭", subject: "MEMBER_42", now: now).isEmpty) }
        let milliseconds = Date().timeIntervalSince(start) * 1000 / 200
        print("QQ memory retrieval benchmark: 256 facts, mean \(milliseconds) ms/query")
        #expect(milliseconds < 50)
        #expect(index.search("晚饭", subject: "MEMBER_42", now: now.addingTimeInterval(366 * 86400)).isEmpty)
    }
}
