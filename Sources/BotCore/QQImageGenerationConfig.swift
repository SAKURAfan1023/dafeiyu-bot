import Foundation

public enum QQImageProvider: String, Codable, CaseIterable, Sendable {
    case zhipu, cloudflare
    public var title: String { self == .zhipu ? "智谱 CogView-3-Flash" : "Cloudflare FLUX.1 schnell" }
    public var alternate: QQImageProvider { self == .zhipu ? .cloudflare : .zhipu }
}

// Credentials are deliberately excluded from Codable settings.
public struct QQImageGenerationConfig: Codable, Equatable, Sendable {
    public var enabled = false
    public var primary: QQImageProvider = .zhipu
    public var fallbackEnabled = true
    public var cloudflareAccountID = ""
    public init() {}
    public func validate() throws {
        guard cloudflareAccountID.isEmpty || cloudflareAccountID.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil else {
            throw CoreError.invalid("Cloudflare Account ID 应为 32 位十六进制字符（不是 API Token）")
        }
    }
}
