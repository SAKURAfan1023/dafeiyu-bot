import Foundation
import Testing
@testable import WeChatAIBot

@Test func platformLockExcludesAnotherOwnerAndReleasesOnClose() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dafeiyu-lock-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("lock")
    var first: PlatformFileLock? = try PlatformFileLock(url: url, message: "held")
    #expect(throws: (any Error).self) { try PlatformFileLock(url: url, message: "held") }
    withExtendedLifetime(first) {}
    first = nil
    let second = try PlatformFileLock(url: url, message: "held")
    withExtendedLifetime(second) {}
}
