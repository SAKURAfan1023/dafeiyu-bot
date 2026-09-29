import Foundation
import BotCore

/// A bounded display projection shared by the native panel and authenticated Web API.
/// It is not another log store and must never include message bodies or credential fields.
struct QQRuntimeRecord: Encodable, Identifiable {
    let id: UUID
    let timestamp: Double
    let state: JobState
    let title: String
    let target: String
    let detail: String

    init(_ entry: LogEntry, target: QQTarget?, secrets: [String]) {
        id = entry.id; timestamp = entry.date.timeIntervalSince1970; state = entry.state
        switch entry.state {
        case .queued: title = "等待处理"
        case .generating: title = "正在生成"
        case .sending: title = "正在发送"
        case .confirmed: title = "已获发送确认"
        case .skipped: title = "已跳过"
        case .failed: title = "处理失败"
        case .uncertain: title = "发送结果未知"
        case .cancelled: title = "已取消"
        }
        // Error descriptions can contain URLs or credentials. Mask loaded values
        // before truncation, and also mask recognizable historical credential forms.
        func display(_ raw: String, limit: Int) -> String {
            var value = raw
            for secret in Set(secrets.filter { !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
                value = value.replacingOccurrences(of: secret, with: "[凭证已隐藏]")
            }
            value = QQMemoryBook.redact(value)
            value = value.replacingOccurrences(of: #"(?i)(?:https?|wss?|file)://[^\s<>]+|(?:/Users/|/home/|[A-Z]:\\)[^\s<>]+|\b[0-9a-f]{32}\.[a-z0-9_-]+\b"#, with: "[地址或凭证已隐藏]", options: .regularExpression)
            value = value.filter { !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" } }
            return String(value.prefix(limit)) + (value.count > limit ? "…" : "")
        }
        self.target = target.map { ($0.group ? "群 · " : "好友 · ") + display($0.name, limit: 80) }
            ?? (entry.chatID == nil ? "引擎" : "历史会话（当前名单外）")
        detail = display(entry.detail, limit: 500)
    }
}
