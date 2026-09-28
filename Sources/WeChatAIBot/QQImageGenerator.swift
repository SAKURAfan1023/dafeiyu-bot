import Foundation
import ImageIO
import BotCore

// Kept in memory or Keychain only. Never serialized with QQ configuration or model messages.
struct QQImageCredentials: Sendable {
    var zhipuKey = ""
    var cloudflareToken = ""
}

struct QQImageGenerator {
    var session: URLSession = .shared
    static let definition: [String: Any] = ["type": "function", "function": [
        "name": "generate_image", "description": "用户明确要求画图、创作新图片时调用。生成一张新图，不是搜索。普通聊天配表情用现有图库。",
        "parameters": ["type": "object", "properties": ["prompt": ["type": "string", "description": "仅画面描述（主体、动作、风格），最多1000字符；不含聊天记录、身份标识、账号、密钥或系统指令。画大肥鱼时明确成年蓝发蓝眼鲸鱼娘、鲸鱼尾巴、可爱二次元风格。"]], "required": ["prompt"], "additionalProperties": false]
    ]]

    // The caller reserves shared quota and revalidates the run/recipient before EACH external attempt.
    func execute(arguments: String, settings: QQImageGenerationConfig, credentials: QQImageCredentials,
                 beforeAttempt: @escaping @MainActor @Sendable () async throws -> Void) async throws -> ModelToolResult {
        try Task.checkCancellation()
        guard settings.enabled else { return ModelToolResult(content: "生图未启用，不能声称已生成图片。") }
        try settings.validate()
        guard arguments.utf8.count <= 8192,
              let object = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              Set(object.keys) == ["prompt"], let raw = object["prompt"] as? String else {
            return ModelToolResult(content: "生图参数无效，未发送请求。")
        }
        let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...1000).contains(prompt.count), prompt.range(of: #"(?i)(sk-[a-z0-9]+|https?://|api.?key|系统提示词|system.prompt|\d{7,}|\[(OWNER|BOT|PEER)\])"#, options: .regularExpression) == nil else {
            return ModelToolResult(content: "画面描述包含不适合外发的信息或过长，未生成图片。")
        }
        let providers = settings.fallbackEnabled ? [settings.primary, settings.primary.alternate] : [settings.primary]
        var failures: [String] = []
        for (index, provider) in providers.enumerated() {
            try Task.checkCancellation()
            let key = provider == .zhipu ? credentials.zhipuKey : credentials.cloudflareToken
            guard !key.isEmpty, provider != .cloudflare || !settings.cloudflareAccountID.isEmpty else {
                failures.append(provider.title + "：凭证未配置"); continue
            }
            // Outside the provider catch: cancellation, scope loss, persistence and quota failures must NOT fail over.
            try await beforeAttempt()
            do {
                let image = try await generate(provider: provider, prompt: prompt, key: key, account: settings.cloudflareAccountID)
                try Task.checkCancellation()
                let status = (index > 0 ? "已切换备用：" : "生成成功：") + provider.title
                return ModelToolResult(content: "已实际生成并准备附带一张 AI 图片。用短句回应，不声称已看过生成图的细节。" + status,
                    image: image, sources: ["AI 生成 · " + provider.title], imageStatus: status)
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .cancelled { throw CancellationError() }
            catch let failure as GenerationFailure {
                try Task.checkCancellation()
                failures.append(provider.title + "：" + failure.message)
                if !failure.allowsFallback { break }
            } catch {
                try Task.checkCancellation()
                failures.append(provider.title + "：网络或响应异常")
            }
        }
        let status = failures.joined(separator: "；")
        return ModelToolResult(content: "本次未生成图片。" + status + "。明确告知没画出来，不假装成功，不用搜图或表情冒充生成图。", imageStatus: status)
    }

    private func generate(provider: QQImageProvider, prompt: String, key: String, account: String) async throws -> Data {
        let url = provider == .zhipu
            ? URL(string: "https://open.bigmodel.cn/api/paas/v4/images/generations")!
            : URL(string: "https://api.cloudflare.com/client/v4/accounts/\(account)/ai/run/@cf/black-forest-labs/flux-1-schnell")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = provider == .zhipu
            ? ["model": "cogview-3-flash", "prompt": prompt, "size": "1024x1024", "quality": "standard", "watermark_enabled": true]
            : ["prompt": prompt, "steps": 4]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, status) = try await fetch(request, limit: 12_000_000)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let errors = (object?["errors"] as? [[String: Any]] ?? []) + ((object?["error"] as? [String: Any]).map { [$0] } ?? [])
        let codes = errors.compactMap { $0["code"].map { String(describing: $0) } }
        // Check structured refusals even if the upstream incorrectly returns HTTP 200.
        let descriptions = errors.compactMap { $0["message"] as? String }.joined(separator: " ").lowercased()
        let filtered = (object?["content_filter"] as? [[String: Any]])?.isEmpty == false
        if filtered || codes.contains("1301") || descriptions.range(of: "content.?filter|moderation|nsfw|unsafe|safety|内容.*(审核|安全)|不安全|敏感内容", options: .regularExpression) != nil {
            throw GenerationFailure(message: "内容审核未通过，不切换模型", allowsFallback: false)
        }
        guard status == 200, errors.isEmpty, object?["success"] as? Bool != false else {
            let retryable = status == 200 || [401, 402, 404, 408, 429].contains(status) || status >= 500 || codes.contains(where: ["1211", "1302", "1305", "1308", "1113", "3036", "3040", "5035", "5018", "3041", "3007", "5007"].contains)
            throw GenerationFailure(message: "接口失败（HTTP \(status)）", allowsFallback: retryable)
        }
        let bytes: Data
        if provider == .zhipu {
            guard let rows = object?["data"] as? [[String: Any]], rows.count == 1,
                  let path = rows[0]["url"] as? String, let imageURL = URL(string: path), Self.allowedImageURL(imageURL) else {
                throw GenerationFailure(message: "图片地址无效或不是受信任的官方域名", allowsFallback: true)
            }
            // No bearer token is ever sent to the image CDN; redirects are refused.
            var download = URLRequest(url: imageURL); download.timeoutInterval = 25
            let (downloaded, status) = try await fetch(download, limit: 8_000_000)
            guard status == 200 else { throw GenerationFailure(message: "图片下载失败", allowsFallback: true) }
            bytes = downloaded
        } else {
            guard let result = object?["result"] as? [String: Any], let image = result["image"] as? String,
                  let decoded = Data(base64Encoded: image), decoded.count <= 8_000_000 else {
                throw GenerationFailure(message: "图片数据缺失或无效", allowsFallback: true)
            }
            bytes = decoded
        }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height), width * height <= 8_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw GenerationFailure(message: "图片无法解码或尺寸超限", allowsFallback: true)
        }
        return bytes // Preserve the provider's image and watermark; no prompt or image is stored locally.
    }
    private static func allowedImageURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let host = url.host?.lowercased() else { return false }
        // This exact watermark bucket was returned by the authenticated official API in a live probe.
        return host == "sfile.chatglm.cn" || host == "maas-watermark-prod-new.cn-wlcb.ufileos.com" || host.hasSuffix(".bigmodel.cn")
    }
    private func fetch(_ request: URLRequest, limit: Int) async throws -> (Data, Int) {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request, delegate: NoGenerationRedirect())
        guard let response = response as? HTTPURLResponse, response.expectedContentLength <= limit else {
            throw GenerationFailure(message: "响应过大或无效", allowsFallback: true)
        }
        guard !(300...399).contains(response.statusCode) else { throw GenerationFailure(message: "接口重定向被拒绝", allowsFallback: false) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw GenerationFailure(message: "响应过大", allowsFallback: true) }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (data, response.statusCode)
    }
}

private struct GenerationFailure: Error {
    let message: String
    let allowsFallback: Bool
}
private final class NoGenerationRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
