import Foundation

public enum QQVisionProvider: String, Codable, CaseIterable, Sendable {
    case deepseek, zhipu
    public var title: String { self == .zhipu ? "智谱 GLM-4.6V-Flash" : "DeepSeek 原有识图" }
}

// No credentials in persisted settings. Existing installations retain their provider until changed.
public struct QQVisualConfig: Codable, Equatable, Sendable {
    public var provider: QQVisionProvider = .deepseek
    public var googleWebEnabled = false
    public init() {}
}
