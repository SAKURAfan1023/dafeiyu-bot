import Foundation
import Testing
@testable import BotCore

struct QQArtworkTests {
    @Test func hourlySlotsAreIndependentDurableAndDoNotCatchUp() throws {
        var config = QQArtworkConfig(); config.enabled = true; config.scheduleEnabled = true
        #expect(config.effectiveScheduleFrequency == "daily")
        config.scheduleFrequency = "hourly"; config.scheduleMinute = 0
        let due = ISO8601DateFormatter().date(from: "2026-09-28T09:00:00Z")!
        #expect(config.dueDate(now: due.addingTimeInterval(12), since: due.addingTimeInterval(-60)) == due)
        #expect(config.dueDate(now: due.addingTimeInterval(61), since: due.addingTimeInterval(-60)) == nil)
        #expect(config.dueDate(now: due.addingTimeInterval(12), since: due.addingTimeInterval(1)) == nil)
        let key = config.scheduleKey(account: "12345", target: "group:99999", due: due)
        #expect(config.scheduleKey(account: "12345", target: "group:99999", due: due.addingTimeInterval(3600)) != key)
        config.scheduleMinute = 30
        #expect(config.scheduleKey(account: "12345", target: "group:99999", due: due.addingTimeInterval(1800)) == key)
        var ledger = QQArtworkLedger(); ledger.schedules[key] = due
        let restored = try JSONDecoder().decode(QQArtworkLedger.self, from: JSONEncoder().encode(ledger))
        #expect(restored.schedules[key] == due)
        config.scheduleTimeZone = "America/Los_Angeles"
        let repeated = ISO8601DateFormatter().date(from: "2026-11-01T08:30:00Z")!
        #expect(config.scheduleKey(account: "12345", target: "A", due: repeated) != config.scheduleKey(account: "12345", target: "A", due: repeated.addingTimeInterval(3600)))
        config.scheduleFrequency = "invalid"; #expect(throws: (any Error).self) { try config.validate() }
    }
    @Test func artistInputsAreRestrictedToPixivProfilesAndOldSettingsDecode() throws {
        for input in [" 999111 ", "https://www.pixiv.net/users/999111", "https://pixiv.net/en/users/999111/?utm_source=test"] {
            #expect(try QQArtworkConfig.artistID(from: input) == "999111")
        }
        for input in ["https://www.pixiv.net.evil.org/users/999111", "https://localhost/users/999111", "https://name@www.pixiv.net/users/999111", "https://www.pixiv.net:443/users/999111", "https://www.pixiv.net/artworks/999111", "https://www.pixiv.net/users/999111/extra", "http://www.pixiv.net/users/999111", "https://www.pixiv.net/users/%39%39%39%31%31%31/../artworks"] {
            #expect(throws: (any Error).self) { try QQArtworkConfig.artistID(from: input) }
        }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(QQArtworkConfig())) as! [String: Any]
        object.removeValue(forKey: "artistNames")
        var restored = try JSONDecoder().decode(QQArtworkConfig.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.artistNames == nil)
        restored.artistNames = ["999111": "not in roster"]
        #expect(throws: (any Error).self) { try restored.validate() }
    }
    @Test func searchThresholdDefaultsAndRoundTrips() throws {
        var config = try JSONDecoder().decode(QQArtworkConfig.self, from: JSONEncoder().encode(QQArtworkConfig()))
        #expect(config.searchMinBookmarks == nil)
        #expect(config.effectiveSearchMinBookmarks == 1000)
        config.effectiveSearchMinBookmarks = 5000
        #expect(try JSONDecoder().decode(QQArtworkConfig.self, from: JSONEncoder().encode(config)).effectiveSearchMinBookmarks == 5000)
        for invalid in [0, -1, 1_000_001] {
            config.effectiveSearchMinBookmarks = invalid
            #expect(throws: (any Error).self) { try config.validate() }
        }
    }
    @Test func explicitCommandsAreBoundedAndExact() {
        #expect(QQArtworkRequest.parse(" /hot 风景 ") == .init(mode: "hot", query: "风景"))
        #expect(QQArtworkRequest.parse("/artist Mika Pikazo")?.query == "Mika Pikazo")
        #expect(QQArtworkRequest.parse("/next")?.mode == "next")
        #expect(QQArtworkRequest.parse("/hot原神") == .init(mode: "hot", query: "原神"))
        #expect(QQArtworkRequest.parse("/search 原神") == .init(mode: "search", query: "原神"))
        #expect(QQArtworkRequest.parse("/search原神") == .init(mode: "search", query: "原神"))
        #expect(QQArtworkRequest.parse("/search")?.mode == "help")
        #expect(QQArtworkRequest.parse("/searching") == nil)
        #expect(QQArtworkRequest.parse("/next 蓝发 -黑丝") == .init(mode: "next", query: "蓝发 -黑丝"))
        #expect(QQArtworkRequest.parse("/artist Mika Pikazo 白发")?.query == "Mika Pikazo 白发")
        #expect(QQArtworkRequest.parse("/artists")?.mode == "artists")
        #expect(QQArtworkRequest.parse("/art help")?.mode == "help")
        #expect(QQArtworkRequest.parse("/art https://127.0.0.1")?.mode == "help")
        #expect(QQArtworkRequest.parse("/art a\nb")?.mode == "help")
        #expect(QQArtworkRequest.parse("please /hot") == nil)
        #expect(QQArtworkRequest.parse("/hotdog") == nil)
    }
    @Test func scheduleUsesLocalDayAndDoesNotCatchUp() throws {
        var config = QQArtworkConfig(); config.enabled = true; config.scheduleEnabled = true
        let due = ISO8601DateFormatter().date(from: "2026-09-28T11:00:00Z")!
        #expect(config.dueDate(now: due.addingTimeInterval(12), since: due.addingTimeInterval(-60)) == due)
        #expect(config.dueDate(now: due.addingTimeInterval(61), since: due.addingTimeInterval(-60)) == nil)
        #expect(config.dueDate(now: due.addingTimeInterval(12), since: due.addingTimeInterval(1)) == nil)
        #expect(config.dueDate(now: due.addingTimeInterval(-1), since: due.addingTimeInterval(-60)) == nil)
        let key = config.scheduleKey(account: "12345", target: "group:99999", due: due)
        config.scheduleHour = 20
        #expect(config.scheduleKey(account: "12345", target: "group:99999", due: due.addingTimeInterval(3600)) == key)
        config.scheduleTimeZone = "unknown"; #expect(throws: (any Error).self) { try config.validate() }
    }
    @Test func durableLedgerSeparatesChatsAndConservativelyRecovers() throws {
        var ledger = QQArtworkLedger(); let ticket = UUID()
        ledger.reserve(ticket: ticket, scope: "A", id: "pixiv:1", hash: "hash", request: .init(mode: "hot"))
        var restored = try JSONDecoder().decode(QQArtworkLedger.self, from: JSONEncoder().encode(ledger)); restored.recover()
        #expect(restored.deliveries[0].state == "unknown")
        #expect(restored.excludes(scope: "A", id: "other", hash: "hash", days: 30))
        #expect(!restored.excludes(scope: "B", id: "pixiv:1", days: 30))
        #expect(!restored.allowed(scope: "A", limit: 1))
        #expect(restored.continuation["A"]?.mode == "hot")
        #expect(restored.continuation["B"] == nil)
        restored.continuation["B"] = .init(mode: "artist", query: "17429", prompt: "白发")
        restored.trim()
        let reloaded = try JSONDecoder().decode(QQArtworkLedger.self, from: JSONEncoder().encode(restored))
        #expect(reloaded.continuation["B"]?.prompt == "白发")
        let legacy = try JSONDecoder().decode(QQArtworkRequest.self, from: Data(#"{"mode":"hot","query":"原神"}"#.utf8))
        #expect(legacy.prompt == nil); #expect(legacy.query == "原神")
        try restored.reserveNetwork(limit: 1)
        #expect(throws: (any Error).self) { try restored.reserveNetwork(limit: 1) }
    }
    @Test func oldQQConfigDecodesWithFeatureDisabled() throws {
        let data = try JSONEncoder().encode(QQConfig())
        let config = try JSONDecoder().decode(QQConfig.self, from: data)
        #expect(!config.effectiveArtwork.enabled)
        #expect(!config.effectiveArtwork.scheduleEnabled)
    }
}
