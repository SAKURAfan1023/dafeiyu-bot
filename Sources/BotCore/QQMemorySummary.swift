import Foundation

/// A bounded, untrusted summary; never a system instruction or a credential store.
public struct QQMemorySummary: Codable, Equatable, Sendable {
    public let text: String
    public let updatedAt: Date
    public var expired: Bool { Date().timeIntervalSince(updatedAt) > 90 * 86400 }
    public static func decode(_ raw: String, now: Date = Date()) throws -> QQMemorySummary {
        guard raw.utf8.count <= 24000, let data = raw.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["summary"], let value = object["summary"] as? String, !value.isEmpty else {
            throw CoreError.invalid("记忆摘要格式无效")
        }
        let redacted = value.replacingOccurrences(of: #"(?i)(sk-[a-z0-9_-]+|bearer\s+[a-z0-9._-]+|(?:密码|口令|密钥|token|api.?key)\s*[:：=]\s*[^\s，。；;]+|https?://[^\s]+[?][^\s]+)"#, with: "[敏感信息已省略]", options: .regularExpression)
        return QQMemorySummary(text: String(redacted.prefix(2000)), updatedAt: now)
    }
}
