import Foundation
import Testing
import BotCore
@testable import WeChatAIBot

struct QQStickerTests {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/QQStickers")
    @Test func everyBundledImagePassesIntegrityAndDecodeChecks() throws {
        let library = QQStickerLibrary(directory: directory)
        #expect(library.items.count == 4)
        for item in library.items { #expect(library.data(for: item) != nil) }
    }
    @Test func contentCooldownSurvivesSerializationAndExpires() throws {
        let library = QQStickerLibrary(directory: directory), now = Date()
        var used: [QQStickerLibrary.Use] = []
        for _ in library.items {
            let item = try #require(library.available(recent: used, now: now).first)
            #expect(!used.contains { $0.sha256 == item.sha256 })
            used.append(.init(sha256: item.sha256, at: now))
        }
        let restored = try JSONDecoder().decode([QQStickerLibrary.Use].self, from: JSONEncoder().encode(used))
        #expect(library.available(recent: restored, now: now.addingTimeInterval(86399)).isEmpty)
        #expect(library.available(recent: restored, now: now.addingTimeInterval(86401)).count == library.items.count)
        let pool = QQStickerLibrary.shortlist(library.items, emotion: .sleepy)
        #expect(pool.count <= 16)
        #expect(pool.allSatisfy { $0.emotion == .sleepy || $0.emotion == .neutral })
        #expect(!pool.contains { $0.emotion == .annoyed || $0.emotion == .teasing })
        #expect(QQStickerLibrary.shortlist([], emotion: .joy).isEmpty)
    }
    @Test func tamperedOrMissingFilesCannotBecomeOutgoingMedia() throws {
        let library = QQStickerLibrary(directory: directory)
        let item = try #require(library.items.first)
        let changed = QQStickerLibrary.Item(id: item.id, title: item.title, emotion: item.emotion, file: item.file, sha256: "bad", source: item.source)
        #expect(library.data(for: changed) == nil)
        let traversal = QQStickerLibrary.Item(id: item.id, title: item.title, emotion: item.emotion, file: "../secret.png", sha256: item.sha256, source: item.source)
        #expect(library.data(for: traversal) == nil)
        #expect(QQStickerLibrary(directory: nil).items.isEmpty)
    }
}
