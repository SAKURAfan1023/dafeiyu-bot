import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot

struct QQStickerTests {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/QQStickers")
    @Test func communityCatalogImportsIndependentlyWithoutChangingBuiltInPack() throws {
        let community = directory.deletingLastPathComponent().appendingPathComponent("PhotoStickers")
        let catalog = QQStickerLibrary(directory: community)
        let records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: community.appendingPathComponent("manifest.json"))) as? [[String: Any]])
        #expect(catalog.items.count >= 50)
        #expect(catalog.items.count == records.count)
        #expect(catalog.items.allSatisfy { $0.character == "deepseek-whale-maid" })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var local = QQStickerLibrary(directory: nil, localDirectory: folder)
        for item in catalog.items {
            let bytes = try #require(catalog.data(for: item))
            try local.importImage(bytes, title: item.title, emotion: item.emotion, context: item.context ?? "", source: item.source,
                                  author: item.author ?? "", license: item.license ?? "", publicSharing: false)
        }
        #expect(local.items.count == catalog.items.count)
        #expect(local.items.allSatisfy { $0.publicSharing == false })
        #expect(QQStickerLibrary(directory: directory).items.count == 37)
    }
    @Test func resourcePackValidatesBeforeImportAndRetainsPerImageMetadata() throws {
        let item = try #require(QQStickerLibrary(directory: directory).items.first)
        let bytes = try Data(contentsOf: directory.appendingPathComponent(item.file))
        let record: [String: Any] = ["title":"合成问候", "emotion":"neutral", "context":"普通问候", "source":"https://example.com/sticker",
                                   "author":"synthetic", "license":"CC0-1.0", "sha256":item.sha256, "imageBase64":bytes.base64EncodedString()]
        let pack: [String: Any] = ["format":"dafeiyu-stickers", "version":1, "items":[record], "runtimeSettings":["enabled":true]]
        let decoded = try QQStickerPack.decode(JSONSerialization.data(withJSONObject: pack))
        #expect(decoded.count == 1)
        #expect(decoded[0].data == bytes)
        #expect(decoded[0].context == "普通问候")
        #expect(decoded[0].author == "synthetic")
        for mode in ["version", "empty", "duplicate", "hash", "source", "title", "count"] {
            var changed = pack, invalid = record
            switch mode {
            case "version": changed["version"] = 2
            case "empty": changed["items"] = []
            case "duplicate": changed["items"] = [record, record]
            case "hash": invalid["sha256"] = String(repeating: "0", count: 64); changed["items"] = [invalid]
            case "source": invalid["source"] = "file:///synthetic"; changed["items"] = [invalid]
            case "title": invalid["title"] = ""; changed["items"] = [invalid]
            default: changed["items"] = Array(repeating: record, count: 51)
            }
            #expect(throws: (any Error).self) { try QQStickerPack.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
    }
    @Test func everyBundledImagePassesIntegrityAndDecodeChecks() throws {
        let library = QQStickerLibrary(directory: directory)
        #expect(library.items.count == 37)
        #expect(library.items.allSatisfy { $0.character == "deepseek-whale-maid" })
        #expect(!library.items.contains { $0.id.hasPrefix("pysio-") })
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
        var bundled = QQStickerLibrary(directory: directory, localDirectory: FileManager.default.temporaryDirectory)
        let bytes = try Data(contentsOf: directory.appendingPathComponent(item.file))
        #expect(throws: (any Error).self) { try bundled.importImage(bytes, title: "重复的内置图", emotion: .joy, context: "", source: "", author: "", license: "", publicSharing: false) }
    }
    @Test func localImportPersistsMetadataAndRejectsDuplicatesAndUnsafeFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library = QQStickerLibrary(directory: nil, localDirectory: folder)
        let bytes = try Data(contentsOf: directory.appendingPathComponent("neutral.png"))
        #expect(throws: (any Error).self) { try library.importImage(Data("not an image".utf8), title: "测试", emotion: .joy, context: "轻松庆祝", source: "", author: "", license: "", publicSharing: false) }
        #expect(throws: (any Error).self) { try library.importImage(bytes, title: "测试", emotion: .joy, context: "", source: "file:///secret", author: "", license: "", publicSharing: false) }
        #expect(throws: (any Error).self) { try library.importImage(bytes, title: "测试", emotion: .joy, context: "", source: "", author: "", license: "", publicSharing: true) }
        try library.importImage(bytes, title: "测试招呼", emotion: .neutral, context: "普通问候", source: "", author: "", license: "", publicSharing: false)
        let item = try #require(library.items.first)
        #expect(library.data(for: item) != nil)
        #expect(item.publicSharing == false)
        #expect(throws: (any Error).self) { try library.importImage(bytes, title: "换个文件名仍是同图", emotion: .joy, context: "", source: "", author: "", license: "", publicSharing: false) }
        let restored = QQStickerLibrary(directory: nil, localDirectory: folder)
        #expect(restored.items.count == 1)
        #expect(restored.items.first?.context == "普通问候")
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("manifest.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(restored.available(recent: [.init(sha256: item.sha256, at: Date())], now: Date().addingTimeInterval(7201), repeatHours: 1).count == 1)
        #expect(restored.available(recent: [.init(sha256: item.sha256, at: Date())], now: Date().addingTimeInterval(7201), repeatHours: 24).isEmpty)
    }
}
