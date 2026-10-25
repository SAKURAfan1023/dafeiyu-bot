import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import BotCore

// A resource pack contains bytes and descriptive metadata, never paths, URLs to fetch or runtime settings.
struct QQStickerPack {
    struct Item {
        let title: String
        let emotion: QQEmotion
        let context: String
        let source: String
        let author: String
        let license: String
        let data: Data
    }
    private struct Envelope: Decodable {
        let format: String
        let version: Int
        let items: [WireItem]
    }
    private struct WireItem: Decodable {
        let title: String
        let emotion: QQEmotion
        let context: String
        let source: String
        let author: String
        let license: String
        let sha256: String
        let imageBase64: String
    }
    static func decode(_ data: Data) throws -> [Item] {
        guard (1...24_000_000).contains(data.count) else { throw AppFailure.message("资源包最多 24 MB") }
        let pack = try JSONDecoder().decode(Envelope.self, from: data)
        guard pack.format == "dafeiyu-stickers", pack.version == 1, (1...50).contains(pack.items.count) else { throw AppFailure.message("请选择有效的表情资源包，每包 1–50 张") }
        var hashes = Set<String>()
        return try pack.items.map { item in
            let url = URL(string: item.source)
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.title.count <= 80,
                  item.context.count <= 300, item.author.count <= 80, item.license.count <= 100, item.source.count <= 500,
                  item.source.isEmpty || (url?.scheme == "https" && url?.host != nil && url?.user == nil && url?.password == nil && url?.query == nil && url?.fragment == nil),
                  item.imageBase64.utf8.count <= 4_000_000, let bytes = Data(base64Encoded: item.imageBase64), (1...3_000_000).contains(bytes.count),
                  SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == item.sha256,
                  hashes.insert(item.sha256).inserted else { throw AppFailure.message("资源包包含无效元数据、重复图片或校验不符的内容，未开始导入") }
            return Item(title: item.title, emotion: item.emotion, context: item.context, source: item.source, author: item.author, license: item.license, data: bytes)
        }
    }
}
