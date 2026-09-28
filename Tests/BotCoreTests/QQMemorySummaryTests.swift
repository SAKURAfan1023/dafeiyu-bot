import Foundation
import Testing
@testable import BotCore

struct QQMemorySummaryTests {
    @Test func boundedRedactedAndExpired() throws {
        let raw = try JSONSerialization.data(withJSONObject: ["summary": "喜欢蓝色，API key: sk-syntheticsecret 密码：synthetic123 https://example.org/?token=synthetic " + String(repeating: "鱼", count: 3000)])
        let summary = try QQMemorySummary.decode(String(decoding: raw, as: UTF8.self), now: Date().addingTimeInterval(-91 * 86400))
        #expect(summary.text.count == 2000)
        #expect(!summary.text.contains("synthetic")); #expect(summary.expired)
        #expect(throws: (any Error).self) { try QQMemorySummary.decode(#"{"summary":"x","instruction":"x"}"#) }
    }
    @Test func fencedReplyAndFallbackClassification() {
        let p = QQPersona()
        #expect(!p.decode("```json\n{\"text\":\"你好呀\",\"emotion\":\"joy\",\"intensity\":1}\n```", input: "你好").isFallback)
        #expect(p.decode("plain invalid", input: "你好").isFallback)
    }
}
