import Foundation
import Testing
import BotCore
@testable import WeChatAIBot

@Suite @MainActor struct QQRuntimeRecordTests {
    @Test func presentationHidesCredentialsBeforeTruncatingAndKeepsReasons() throws {
        let syntheticPath = ["", "Users", "synthetic", "file"].joined(separator: "/")
        let entry = LogEntry(state: .failed, detail: "请求失败（HTTP 429） bearer synthetic-bearer sk-synthetic cfut_synthetic token=synthetic-token https://example.invalid/private?key=hidden \(syntheticPath) C:\\Users\\synthetic\\file 0123456789abcdef0123456789abcdef.synthetic actual-loaded-secret " + String(repeating: "长", count: 800))
        let record = QQRuntimeRecord(entry, target: nil, secrets: ["actual-loaded-secret", ""])
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        for forbidden in ["synthetic", "actual-loaded-secret", "example.invalid", "0123456789abcdef"] { #expect(!encoded.contains(forbidden)) }
        #expect(record.title == "处理失败" && record.target == "引擎")
        #expect(record.detail.hasPrefix("请求失败（HTTP 429）"))
        #expect(record.detail.count == 501 && record.detail.hasSuffix("…"))
    }

    @Test func senderLookupAndUnknownDeliveryRemainDistinct() {
        let target = QQTarget(number: "54321", name: "合成好友", group: false)
        let entry = LogEntry(chatID: target.id, state: .uncertain, detail: "发送结果未知，不重发；已暂停 QQ")
        let record = QQRuntimeRecord(entry, target: target, secrets: [])
        #expect(record.title == "发送结果未知" && record.target == "好友 · 合成好友")
        #expect(record.detail.contains("不重发"))
        #expect(QQRuntimeRecord(entry, target: nil, secrets: []).target == "历史会话（当前名单外）")
        #expect(QQRuntimeRecord(LogEntry(state: .confirmed, detail: "OneBot 已接受发送；不代表对方已读"), target: nil, secrets: []).title == "已获发送确认")
    }

    @Test func restoredLogsAreBoundedNewestFirstAndDoNotChangeCounters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        seed.save(expectedSelfID: "12345")
        let file = directory.appendingPathComponent("qq-state.json")
        var state = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let entries = (0..<35).map { LogEntry(state: .skipped, detail: "合成原因 \($0)") }
        state["logs"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entries))
        try JSONSerialization.data(withJSONObject: state).write(to: file)
        let restored = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(restored.error == nil)
        #expect(restored.runtimeRecords.count == 30)
        #expect(restored.runtimeRecords.first?.id == entries.last?.id)
        #expect(restored.runtimeRecords.last?.id == entries[5].id)
        #expect(restored.runtimeRecords.allSatisfy { $0.title == "已跳过" })
        #expect(restored.usage.calls == 0 && restored.sends.confirmed == 0 && !restored.running)
    }
}
