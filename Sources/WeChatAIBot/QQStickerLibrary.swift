import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(ImageIO)
import ImageIO
#endif
import BotCore

// Only the bundled, visually reviewed catalog can supply outgoing bytes. No model paths or remote fetching.
struct QQStickerLibrary {
    struct Item: Codable {
        let id: String
        let title: String
        let emotion: QQEmotion
        let file: String
        let sha256: String
        let source: String
        var context: String? = nil
    }
    let directory: URL?
    let items: [Item]
    struct Use: Codable {
        let sha256: String
        let at: Date
    }
    init(directory: URL? = RuntimeResources.directory?.appendingPathComponent("QQStickers")) {
        self.directory = directory
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              data.count < 1_000_000, let catalog = try? JSONDecoder().decode([Item].self, from: data),
              catalog.count <= 500, Set(catalog.map(\.id)).count == catalog.count,
              Set(catalog.map(\.sha256)).count == catalog.count else { items = []; return }
        items = catalog
    }
    // Exact image content cannot repeat in this account/conversation for 24 hours, including after restart.
    func available(recent: [Use], now: Date = Date()) -> [Item] {
        let excluded = Set(recent.filter { now.timeIntervalSince($0.at) < 86400 }.map(\.sha256))
        return items.filter { !excluded.contains($0.sha256) }
    }
    // A bounded caption shortlist, then the existing semantic reviewer chooses or abstains.
    static func shortlist(_ available: [Item], emotion: QQEmotion) -> [Item] {
        let matching = available.filter { $0.emotion == emotion }.shuffled()
        let gentle = emotion == .neutral ? [] : available.filter { $0.emotion == .neutral }.shuffled()
        return Array(matching.prefix(12)) + Array(gentle.prefix(4))
    }
    func data(for item: Item) -> Data? {
        guard let directory, item.file == (item.file as NSString).lastPathComponent,
              ["png", "webp", "jpg", "jpeg"].contains((item.file as NSString).pathExtension),
              let size = try? directory.appendingPathComponent(item.file).resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
              size.isSymbolicLink == false, let bytes = size.fileSize, (1...3_000_000).contains(bytes),
              let data = try? Data(contentsOf: directory.appendingPathComponent(item.file)), data.count == bytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == item.sha256 else { return nil }
        #if os(Linux)
        guard (try? LinuxImages.process(data, mode: "sticker")) != nil else { return nil }
        #else
        guard let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height) else { return nil }
        #endif
        return data
    }
}
