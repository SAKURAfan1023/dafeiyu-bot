import Foundation
import Testing
@testable import BotCore

struct PolicyTests {
    private func m(_ text: String, _ direction: Direction = .incoming) -> ObservedMessage { ObservedMessage(text, direction: direction) }
    @Test func testInitialHistoryDoesNotBecomeNewMessages() {
        #expect((MessagePolicy.delta(previous: [], current: [m("旧消息")])) == (.resync))
    }
    @Test func testRepeatedTextPreservesOccurrenceOrder() {
        #expect((MessagePolicy.delta(previous: [m("锚点"), m("你好")], current: [m("锚点"), m("你好"), m("你好")])) == (.appended([m("你好")])))
    }
    @Test func testScrollingKeepsOverlapWithoutReplayingOldContent() {
        #expect((MessagePolicy.delta(previous: [m("a"), m("b"), m("c")], current: [m("b"), m("c"), m("d")])) == (.appended([m("d")])))
        #expect((MessagePolicy.delta(previous: [m("b"), m("c")], current: [m("a"), m("b")])) == (.resync))
    }
    @Test func testMissingAnchorNeverRepliesToLastMessageAsFallback() {
        #expect((MessagePolicy.delta(previous: [m("a")], current: [m("旧内容")])) == (.resync))
    }
    @Test func testOwnAndUnknownDirectionsRejected() {
        let rule = ChatRule(name: "测试", enabled: true, bound: true)
        #expect((MessagePolicy.rejection(m("我自己的消息", .outgoing), rule: rule)) != nil)
        #expect((MessagePolicy.rejection(m("无法确认", .unknown), rule: rule)) != nil)
        #expect((MessagePolicy.rejection(m("正常收到"), rule: rule)) == nil)
    }
    @Test func testGroupTextMentionNotEnough() {
        let rule = ChatRule(name: "测试群", kind: .group, enabled: true, selfName: "小明", bound: true)
        #expect((MessagePolicy.rejection(ObservedMessage("@小明 你好", direction: .incoming, mention: .textOnly), rule: rule)) != nil)
        #expect((MessagePolicy.rejection(ObservedMessage("@小明 你好", direction: .incoming, mention: .verified), rule: rule)) == nil)
    }
    @Test func testMentionRequiresExactBoundaryAndEscapesRegex() {
        #expect(MessagePolicy.hasMentionText("@小明 你好", selfName: "小明"))
        #expect(MessagePolicy.hasMentionText("@A.B\u{2005}你好", selfName: "A.B"))
        #expect(!(MessagePolicy.hasMentionText("@小明同学 你好", selfName: "小明")))
        #expect(!(MessagePolicy.hasMentionText("@AxB 你好", selfName: "A.B")))
        #expect(!(MessagePolicy.hasMentionText("@其他人 你好", selfName: "")))
    }
    @Test func testUnboundAndDisabledChatsNeverSend() {
        #expect((MessagePolicy.rejection(m("hello"), rule: ChatRule(name: "测试", enabled: true))) != nil)
        #expect((MessagePolicy.rejection(m("hello"), rule: ChatRule(name: "测试", bound: true))) != nil)
    }
    @Test func testNonTextRejected() {
        #expect((MessagePolicy.rejection(ObservedMessage("[语音]", direction: .incoming, isText: false), rule: ChatRule(name: "测试", enabled: true, bound: true))) != nil)
    }
    @Test func testPauseAndRestartInvalidateInFlightReplies() {
        var fence = RunFence(); fence.start(); let epoch = fence.epoch
        #expect(fence.permits(epoch)); fence.stop(); #expect(!(fence.permits(epoch)))
        fence.start(); #expect(!(fence.permits(epoch))); #expect(fence.permits(fence.epoch))
    }
    @Test func testDailyBudgetCountsEachAttemptAndResets() {
        var usage = Usage(); let today = Date()
        let first = usage.reserve(limit: 2, now: today), second = usage.reserve(limit: 2, now: today)
        let third = usage.reserve(limit: 2, now: today)
        #expect(first && second && !third); #expect(usage.calls == 2)
        let tomorrow = usage.reserve(limit: 2, now: today.addingTimeInterval(86400))
        #expect(tomorrow); #expect(usage.calls == 1)
    }
    @Test func testCrossMidnightWindow() {
        var config = BotConfig(); config.workHoursEnabled = true; config.workStart = 22; config.workEnd = 7
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: h))! }
        #expect(config.inWorkHours(at: date(23), calendar: cal)); #expect(config.inWorkHours(at: date(6), calendar: cal))
        #expect(!(config.inWorkHours(at: date(7), calendar: cal))); #expect(!(config.inWorkHours(at: date(12), calendar: cal)))
    }
    @Test func testConfigRejectsDuplicatesAndUnverifiedActivation() {
        var c = BotConfig(); c.chats = [ChatRule(name: "重复"), ChatRule(name: "重复")]
        #expect(throws: (any Error).self) { try c.validate() }
        c.chats = [ChatRule(name: "未验证", enabled: true)]; #expect(throws: (any Error).self) { try c.validate() }
        c.chats = [ChatRule(name: "群", kind: .group, enabled: true, bound: true)]; #expect(throws: (any Error).self) { try c.validate() }
    }
    @Test func testConfigDoesNotContainSecrets() throws {
        let data = try JSONEncoder().encode(BotConfig())
        let text = String(decoding: data, as: UTF8.self).lowercased()
        #expect(!(text.contains("api_key"))); #expect(!(text.contains("apikey"))); #expect(!(text.contains("sk-")))
    }
}
