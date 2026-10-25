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

// Catalog IDs resolve to verified local bytes; model output can never supply a path.
struct QQStickerLibrary {
    struct Item: Codable {
        let id: String
        let title: String
        let emotion: QQEmotion
        let file: String
        let sha256: String
        let source: String
        var context: String? = nil
        var author: String? = nil
        var license: String? = nil
        var publicSharing: Bool? = nil
        var character: String? = nil
    }
    let directory: URL?
    let localDirectory: URL?
    private(set) var items: [Item]
    struct Use: Codable {
        let sha256: String
        let at: Date
    }
    init(directory: URL? = RuntimeResources.directory?.appendingPathComponent("QQStickers"), localDirectory: URL? = nil) {
        self.directory = directory; self.localDirectory = localDirectory
        items = Self.catalog(directory)
        let local = Self.catalog(localDirectory)
        let bundledIDs = Set(items.map(\.id)), bundledHashes = Set(items.map(\.sha256))
        items += local.filter { $0.id.hasPrefix("local-") && !bundledIDs.contains($0.id) && !bundledHashes.contains($0.sha256) }
    }
    private static func catalog(_ directory: URL?) -> [Item] {
        guard let directory, (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { return [] }
        let file = directory.appendingPathComponent("manifest.json")
        guard let metadata = try? file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), metadata.isSymbolicLink == false,
              let size = metadata.fileSize, (1..<1_000_000).contains(size), let data = try? Data(contentsOf: file),
              data.count == size, let catalog = try? JSONDecoder().decode([Item].self, from: data),
              catalog.count <= 500, Set(catalog.map(\.id)).count == catalog.count,
              Set(catalog.map(\.sha256)).count == catalog.count else { return [] }
        return catalog
    }
    // Content cooldown is per account/conversation and survives restart.
    func available(recent: [Use], now: Date = Date(), repeatHours: Int = 24) -> [Item] {
        let excluded = Set(recent.filter { now.timeIntervalSince($0.at) < Double(repeatHours) * 3600 }.map(\.sha256))
        return items.filter { !excluded.contains($0.sha256) }
    }
    // A bounded caption shortlist, then the existing semantic reviewer chooses or abstains.
    static func shortlist(_ available: [Item], emotion: QQEmotion) -> [Item] {
        let matching = available.filter { $0.emotion == emotion }.shuffled()
        let gentle = emotion == .neutral ? [] : available.filter { $0.emotion == .neutral }.shuffled()
        return Array(matching.prefix(12)) + Array(gentle.prefix(4))
    }
    func data(for item: Item) -> Data? {
        let directory = item.id.hasPrefix("local-") ? localDirectory : directory
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

    mutating func importImage(_ bytes: Data, title: String, emotion: QQEmotion, context: String, source: String, author: String, license: String, publicSharing: Bool) throws {
        guard let localDirectory, (1...3_000_000).contains(bytes.count), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 80, context.count <= 300, source.count <= 500, author.count <= 80, license.count <= 100 else { throw AppFailure.message("图片最多 3 MB；名称 1–80 字，情境最多 300 字") }
        let sourceURL = URL(string: source)
        guard source.isEmpty || (sourceURL?.scheme == "https" && sourceURL?.host != nil && sourceURL?.user == nil && sourceURL?.password == nil && sourceURL?.query == nil && sourceURL?.fragment == nil) else { throw AppFailure.message("来源请填写不含凭证、查询参数的公开 HTTPS 网页") }
        guard !publicSharing || (!author.isEmpty && !license.isEmpty && !source.isEmpty) else { throw AppFailure.message("公开分享需要作者、许可和来源；未确认的图片请仅保存在本机") }
        let originalHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard !items.contains(where: { $0.sha256 == originalHash }) else { throw AppFailure.message("这张图片已存在，未重复导入") }
        let normalized: Data
        #if os(Linux)
        normalized = try LinuxImages.process(bytes, mode: "sticker-import")[0]
        #else
        guard let imageSource = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(imageSource) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height), width * height <= 8_000_000,
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { throw AppFailure.message("请导入静态 PNG、JPEG 或 WebP，尺寸不超过 4096、像素总量不超过 800 万；动图暂不导入发送库") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { throw AppFailure.message("无法转换图片") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AppFailure.message("图片转换失败") }
        normalized = output as Data
        #endif
        guard normalized.count <= 3_000_000 else { throw AppFailure.message("解码后的图片超过 3 MB，请缩小后导入") }
        let hash = SHA256.hash(data: normalized).map { String(format: "%02x", $0) }.joined()
        guard !items.contains(where: { $0.sha256 == hash }) else { throw AppFailure.message("这张图片已存在，未重复导入") }
        guard items.count < 500 else { throw AppFailure.message("表情库最多 500 张") }
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try localDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AppFailure.message("表情目录不能是符号链接") }
        let file = hash + ".png", target = localDirectory.appendingPathComponent(file)
        try normalized.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let item = Item(id: "local-" + hash, title: title, emotion: emotion, file: file, sha256: hash, source: source,
                        context: context, author: author, license: license, publicSharing: publicSharing)
        let catalog = items.filter { $0.id.hasPrefix("local-") } + [item]
        let manifest = localDirectory.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(catalog).write(to: manifest, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
        items.append(item)
    }
}
