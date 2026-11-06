import Foundation
import Testing
@testable import WeChatAIBot

@Test func rapidPrivateReplacementsKeepCompleteSnapshots() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try createPrivateDirectory(directory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("state.json")
    var snapshots: [Data] = []
    for revision in 0..<16 {
        let bytes = Data("{\"revision\":\(revision)}".utf8)
        try writePrivateData(bytes, to: file)
        let snapshot = try Data(contentsOf: file)
        #expect(snapshot == bytes)
        snapshots.append(snapshot)
    }
    #expect(snapshots.first == Data("{\"revision\":0}".utf8))
    #expect(snapshots.last == Data("{\"revision\":15}".utf8))
}

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
