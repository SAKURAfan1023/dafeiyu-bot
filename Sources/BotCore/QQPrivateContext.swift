import Foundation

/// A scoped server snapshot, bounded at the current incoming message (never future replies).
public struct QQPrivateContext: Sendable {
    public let text: String
    public let memoryText: String
    public let messageIDs: Set<String>
    public let memoryEvents: [QQMemoryEvent]
    public static func read(_ rows: [[String: Any]], for message: QQIncoming, selfID: String, excluding: Set<String> = [], botMessageIDs: Set<String> = [], ownershipSince: Double = .infinity) -> QQPrivateContext? {
        guard !message.group, rows.count <= 50,
              let anchor = rows.firstIndex(where: { QQPolicy.identifier($0["message_id"]) == message.id }),
              QQPolicy.identifier((rows[anchor]["sender"] as? [String: Any])?["user_id"]) == message.sender else { return nil }
        var entries: [(id: String, line: String)] = []
        var ids: Set<String> = []
        var memoryEvents: [QQMemoryEvent] = []
        for row in rows.prefix(through: anchor).suffix(20) {
            guard row["message_type"] as? String == "private", row["sub_type"] as? String == "friend",
                  QQPolicy.identifier(row["self_id"]) == selfID,
                  let id = QQPolicy.identifier(row["message_id"]), Int64(id) != nil,
                  let author = QQPolicy.identifier((row["sender"] as? [String: Any])?["user_id"]),
                  author == selfID || author == message.target,
                  let segments = row["message"] as? [[String: Any]] else { return nil }
            if let user = QQPolicy.identifier(row["user_id"]), user != author { return nil }
            guard ids.insert(id).inserted else { continue }
            if id == message.id { continue } // Current text and actual images are supplied separately.
            var text = ""
            for segment in segments {
                let data = segment["data"] as? [String: Any] ?? [:]
                switch segment["type"] as? String {
                case "text": text += String((data["text"] as? String ?? "").prefix(max(0, 800 - text.count)))
                case "image": text += "[此前图片/表情，画面未附入，不猜图意]"
                case "reply": text += "[引用此前消息]"
                case "face": text += "[QQ表情]"
                default: text += "[其他消息]"
                }
            }
            let speaker: String
            if author != selfID { speaker = "[PEER] 当前好友" }
            else if botMessageIDs.contains(id) { speaker = "[BOT] 大肥鱼此前自动回复" }
            else if let time = row["time"] as? Double, time >= ownershipSince { speaker = "[OWNER] 本账号主人/开发者的人工发言" }
            else { speaker = "[SELF_UNKNOWN] 本账号旧发言，无法区分主人或机器人，勿强行归属" }
            let role = author != selfID ? "PEER" : botMessageIDs.contains(id) ? "BOT" : speaker.hasPrefix("[OWNER]") ? "OWNER" : "SELF_UNKNOWN"
            memoryEvents.append(QQMemoryEvent(id: id, subject: role, text: text, at: Date(timeIntervalSince1970: row["time"] as? Double ?? message.time)))
            let item = ["speaker": speaker, "recipient": author == selfID ? "[PEER] 当前好友" : "[SELF] 本账号（大肥鱼与主人共用）", "text": String(text.prefix(1000))]
            guard let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]) else { return nil }
            entries.append((id, String(decoding: data, as: UTF8.self)))
        }
        while entries.reduce(0, { $0 + $1.line.count }) > 6500 { entries.removeFirst() }
        return QQPrivateContext(text: entries.map(\.line).joined(separator: "\n"),
            memoryText: entries.filter { !excluding.contains($0.id) }.map(\.line).joined(separator: "\n"), messageIDs: ids, memoryEvents: memoryEvents)
    }
}
