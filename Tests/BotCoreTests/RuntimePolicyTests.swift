import Foundation
import Testing
@testable import BotCore

struct RuntimePolicyTests {
    @Test func idleProbeBacksOffAndStillDetectsMissingEvents() {
        var schedule = ReadSchedule()
        func due(now: TimeInterval, event: Bool) -> Bool { schedule.isDue(now: now, event: event) }
        #expect((due(now: 0, event: false)))
        schedule.didRead(now: 0, changed: true)
        #expect((!due(now: 0.9, event: false)))
        #expect((due(now: 1, event: false)))
        schedule.didRead(now: 1, changed: false)
        #expect((!due(now: 2.9, event: false)))
        schedule.didRead(now: 3, changed: false)
        #expect((!due(now: 6.9, event: false)))
        schedule.didRead(now: 7, changed: false)
        #expect((!due(now: 14.9, event: false)))
        #expect((due(now: 15, event: false)))
    }
    @Test func eventBurstCoalescesAndWakesAnIdleReader() {
        var schedule = ReadSchedule()
        func due(now: TimeInterval, event: Bool) -> Bool { schedule.isDue(now: now, event: event) }
        schedule.didRead(now: 0, changed: false)
        for tick in 1...9 { #expect((!due(now: Double(tick) / 10, event: true))) }
        #expect((due(now: 1, event: false)))
        schedule.didRead(now: 1, changed: false)
        #expect((!due(now: 1.1, event: false)))
        #expect((due(now: 2.2, event: true)))
    }
    @Test func globalAndPerChatSendLimitsAreIndependent() throws {
        var limits = SendLimits(); limits.daily = 3; limits.perChatDaily = 2
        var usage = SendUsage(); let chat = UUID(), other = UUID(), now = Date()
        let first = try usage.reserve(chat: chat, limits: limits, chatCooldown: 5, now: now)
        usage.finish(first, confirmed: false, now: now)
        #expect(usage.attempts == 1 && usage.uncertain == 1)
        #expect((usage.allowance(chat: other, limits: limits, chatCooldown: 5, now: now.addingTimeInterval(1)) == .cooldown))
        #expect((usage.allowance(chat: chat, limits: limits, chatCooldown: 5, now: now.addingTimeInterval(4)) == .cooldown))
        let second = try usage.reserve(chat: chat, limits: limits, chatCooldown: 5, now: now.addingTimeInterval(6))
        usage.finish(second, confirmed: true, now: now.addingTimeInterval(6))
        #expect((usage.allowance(chat: chat, limits: limits, chatCooldown: 5, now: now.addingTimeInterval(12)) == .chatLimit))
        _ = try usage.reserve(chat: other, limits: limits, chatCooldown: 5, now: now.addingTimeInterval(12))
        #expect((usage.allowance(chat: UUID(), limits: limits, chatCooldown: 5, now: now.addingTimeInterval(20)) == .globalLimit))
        #expect(usage.attempts == 3 && usage.confirmed == 1 && usage.uncertain == 1)
    }
    @Test func crashRecoveryCountsUnknownOnceWithoutRefunding() throws {
        var usage = SendUsage(); let chat = UUID(), now = Date()
        let ticket = try usage.reserve(chat: chat, limits: SendLimits(), chatCooldown: 5, now: now)
        var restored = try JSONDecoder().decode(SendUsage.self, from: JSONEncoder().encode(usage))
        restored.recoverInterrupted(now: now)
        restored.recoverInterrupted(now: now)
        restored.finish(ticket, confirmed: true, now: now)
        #expect(restored.attempts == 1 && restored.uncertain == 1 && restored.confirmed == 0)
        #expect(restored.byChat[chat.uuidString] == 1)
    }
    @Test func completionIsIdempotentAndDailyRolloverKeepsCooldown() throws {
        var usage = SendUsage(), limits = SendLimits(); limits.globalIntervalSeconds = 10
        let calendar = Calendar.current, chat = UUID()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let ticket = try usage.reserve(chat: chat, limits: limits, chatCooldown: 20, now: midnight.addingTimeInterval(-2))
        usage.finish(ticket, confirmed: true, now: midnight.addingTimeInterval(-1))
        usage.finish(ticket, confirmed: true, now: midnight.addingTimeInterval(-1))
        #expect(usage.confirmed == 1)
        #expect((usage.allowance(chat: chat, limits: limits, chatCooldown: 20, now: midnight) == .cooldown))
        #expect(usage.attempts == 0 && usage.confirmed == 0)
        #expect((usage.allowance(chat: chat, limits: limits, chatCooldown: 20, now: midnight.addingTimeInterval(21)) == .allowed))
    }
    @Test func legacyConfigDecodesAndInvalidLimitsAreRejected() throws {
        var dictionary = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BotConfig())) as! [String: Any]
        dictionary.removeValue(forKey: "sendLimits")
        var config = try JSONDecoder().decode(BotConfig.self, from: JSONSerialization.data(withJSONObject: dictionary))
        #expect(config.effectiveSendLimits.daily == 100)
        config.effectiveSendLimits.daily = 0
        #expect(throws: (any Error).self) { try config.validate() }
    }
}
