#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import BotCore

private typealias StickerViewState<Value> = SwiftUI.State<Value>

func stickerEmotionName(_ emotion: QQEmotion) -> String {
    switch emotion {
    case .neutral: return "平静"
    case .joy: return "开心"
    case .smug: return "得意"
    case .annoyed: return "不满"
    case .sad: return "难过"
    case .sleepy: return "困倦"
    case .flustered: return "害羞"
    case .teasing: return "调侃"
    }
}

struct QQStickerManager: View {
    @ObservedObject var engine: QQEngine
    @Environment(\.dismiss) private var dismiss
    @StickerViewState private var importing = false
    @StickerViewState private var emotion = QQEmotion.neutral
    @StickerViewState private var context = ""
    @StickerViewState private var author = ""
    @StickerViewState private var license = ""
    @StickerViewState private var source = ""
    @StickerViewState private var publicSharing = false
    @StickerViewState private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("表情库 · \(engine.stickerLibrary.items.count) 张").font(.title2.bold()); Spacer(); Button("关闭") { dismiss() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("导入图片的情绪", selection: $emotion) { ForEach(QQEmotion.allCases, id: \.self) { Text(stickerEmotionName($0)).tag($0) } }
                    TextField("适用情境，例如：睡前道晚安，不用于白天问候", text: $context)
                    HStack { TextField("作者", text: $author); TextField("许可，未确认可留空", text: $license) }
                    TextField("公开来源网页 https://", text: $source)
                    Toggle("已确认可公开分享（不会自动上传）", isOn: $publicSharing)
                    Button("导入图片或网页资源包…") { importing = true }
                        .disabled(engine.running || engine.busy || engine.runtimeBusy)
                        .help("网页资源包保留每张图的情绪、适用情境与来源；上方字段仅用于单独导入的图片。资源包不会自动公开或启用回复。")
                    if !status.isEmpty { Text(status).font(.callout).textSelection(.enabled) }
                    Text("静态 PNG / JPEG / WebP，每张最多 3 MB；同图自动去重。公开发布与本机导入分开。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 16) {
                        ForEach(engine.stickerLibrary.items, id: \.id) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                if let bytes = engine.stickerLibrary.data(for: item), let image = NSImage(data: bytes) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(height: 100)
                                }
                                Text(item.title).font(.headline)
                                Text(item.context ?? stickerEmotionName(item.emotion)).font(.caption)
                                Text([item.author, item.license].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.padding(24).frame(width: 720, height: 650).textFieldStyle(PanelTextFieldStyle())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .webP, .json], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                guard (1...50).contains(urls.count) else { throw AppFailure.message("每次选择 1–50 张图片") }
                if urls.contains(where: { $0.pathExtension.lowercased() == "json" }) {
                    guard urls.count == 1, let url = urls.first else { throw AppFailure.message("资源包请单独导入，不与图片混选") }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true, (1...24_000_000).contains(values.fileSize ?? 0) else { throw AppFailure.message("需要 24 MB 内的普通资源包文件") }
                    let items = try QQStickerPack.decode(Data(contentsOf: url))
                    var count = 0, failures: [String] = []
                    for item in items {
                        do {
                            try engine.importSticker(data: item.data, title: item.title, emotion: item.emotion, context: item.context,
                                                     source: item.source, author: item.author, license: item.license, publicSharing: false)
                            count += 1
                        } catch { failures.append(item.title + "：" + error.localizedDescription) }
                    }
                    status = "已导入 \(count) / \(items.count) 张。" + failures.joined(separator: "\n")
                    return
                }
                var count = 0, failures: [String] = []
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true, (1...3_000_000).contains(values.fileSize ?? 0) else { throw AppFailure.message("需要 3 MB 内的普通图片文件") }
                        try engine.importSticker(data: Data(contentsOf: url), title: String(url.deletingPathExtension().lastPathComponent.prefix(80)), emotion: emotion,
                            context: context, source: source, author: author, license: license, publicSharing: publicSharing)
                        count += 1
                    } catch { failures.append(url.lastPathComponent + "：" + error.localizedDescription) }
                }
                status = "已导入 \(count) 张。" + failures.joined(separator: "\n")
            } catch { status = error.localizedDescription }
        }
    }
}
#endif
