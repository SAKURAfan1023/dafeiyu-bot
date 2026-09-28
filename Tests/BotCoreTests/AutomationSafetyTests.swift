import Foundation
import Testing
@testable import BotCore

struct AutomationSafetyTests {
    @Test func strictDraftComparisonRejectsExtraTextAndChangedSpacing() {
        #expect(!SendVerification.matches(expected: "收到", observed: "我的草稿收到", ocr: true))
        #expect(!SendVerification.matches(expected: "a b", observed: "ab", ocr: true))
        #expect(!SendVerification.matches(expected: "收到。", observed: "收到!", ocr: true))
        #expect(!SendVerification.matches(expected: "", observed: "", ocr: false))
        #expect(SendVerification.matches(expected: "收到，谢谢", observed: "收到，\n谢谢", ocr: true))
        #expect(!SendVerification.matches(expected: "收到，谢谢", observed: "收到，\n谢谢", ocr: false))
    }
    @Test func historicalIdenticalReplyIsNotANewSend() {
        let old = [ObservedMessage("你好", direction: .incoming), ObservedMessage("收到", direction: .outgoing)]
        #expect(!SendVerification.hasNewLocalEcho(expected: "收到", before: old, after: old, ocr: true))
        #expect(!SendVerification.hasNewLocalEcho(expected: "收到", before: old, after: old + [ObservedMessage("新问题", direction: .incoming)], ocr: true))
        #expect(SendVerification.hasNewLocalEcho(expected: "收到", before: old, after: old + [ObservedMessage("收到", direction: .outgoing)], ocr: true))
    }
    @Test func FailedOrAmbiguousEchoCannotBeConfirmed() {
        let old = [ObservedMessage("问题", direction: .incoming)]
        for message in [ObservedMessage("答复", direction: .unknown),
                        ObservedMessage("答复", direction: .incoming),
                        ObservedMessage("答复", direction: .outgoing, deliveryFailed: true),
                        ObservedMessage("答复", direction: .outgoing, isText: false)] {
            #expect(!SendVerification.hasNewLocalEcho(expected: "答复", before: old, after: old + [message], ocr: true))
        }
        #expect(!SendVerification.hasNewLocalEcho(expected: "答复", before: [], after: [ObservedMessage("答复", direction: .outgoing)], ocr: true))
        #expect(!SendVerification.hasNewLocalEcho(expected: "答复", before: old,
            after: old + [ObservedMessage("答复", direction: .outgoing), ObservedMessage("人工消息", direction: .outgoing)], ocr: true))
    }
    @Test func SafetyStopSurvivesNewInstanceAndExplicitClear() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("safety.json")
        let first = AutomationInterlock(file: file)
        try first.requireClear()
        try first.trip(reason: "账号异常")
        #expect(throws: (any Error).self) { try first.requireClear() }
        let restarted = AutomationInterlock(file: file)
        #expect(try restarted.currentStop()?.reason == "账号异常")
        #expect(throws: (any Error).self) { try restarted.requireClear() }
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        try restarted.clear()
        try restarted.requireClear()
        try AutomationInterlock(file: file).requireClear()
        // An already stopped process retains its in-memory latch until explicitly cleared.
        #expect(throws: (any Error).self) { try first.requireClear() }
        try first.clear()
    }
    @Test func BrokenPersistenceFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let corrupt = directory.appendingPathComponent("corrupt.json")
        try Data("not json".utf8).write(to: corrupt)
        #expect(throws: (any Error).self) { try AutomationInterlock(file: corrupt).requireClear() }
        let impossible = AutomationInterlock(file: corrupt.appendingPathComponent("cannot-write.json"))
        #expect(throws: (any Error).self) { try impossible.trip(reason: "停机") }
        #expect(throws: (any Error).self) { try impossible.requireClear() }
    }
}
