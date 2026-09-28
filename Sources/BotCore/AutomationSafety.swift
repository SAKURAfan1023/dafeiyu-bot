import Foundation

public struct SafetyStop: Codable, Equatable, Sendable {
    public let reason: String
    public let date: Date
    public init(reason: String, date: Date = Date()) { self.reason = reason; self.date = date }
}

/// Shared by desktop and diagnostic entry points. A malformed/unreadable latch fails closed.
public final class AutomationInterlock {
    private let file: URL
    private var volatileStop: SafetyStop?
    public init(file: URL) { self.file = file }
    public func currentStop() throws -> SafetyStop? {
        if let volatileStop { return volatileStop }
        do { return try JSONDecoder().decode(SafetyStop.self, from: Data(contentsOf: file)) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }
    public func requireClear() throws {
        if let stop = try currentStop() { throw CoreError.invalid("微信自动操作已锁定：" + stop.reason) }
    }
    public func trip(reason: String) throws {
        let stop = SafetyStop(reason: reason)
        volatileStop = stop // Remain stopped even when persistence fails.
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(stop).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    /// Explicit local user action only. Clearing never starts automation.
    public func clear() throws {
        do { try FileManager.default.removeItem(at: file) }
        catch CocoaError.fileNoSuchFile { }
        volatileStop = nil
    }
}

public enum SendVerification {
    public static func matches(expected: String, observed: String, ocr: Bool) -> Bool {
        func normalize(_ text: String) -> String {
            let value = text.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "\r\n", with: "\n")
            // OCR line wrapping is not semantic; spaces and punctuation must remain exact.
            return ocr ? value.replacingOccurrences(of: "\n", with: "") : value
        }
        return !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalize(expected) == normalize(observed)
    }
    public static func hasNewLocalEcho(expected: String, before: [ObservedMessage], after: [ObservedMessage], ocr: Bool) -> Bool {
        guard case .appended(let added) = MessagePolicy.delta(previous: before, current: after) else { return false }
        let outgoing = added.filter { $0.direction == .outgoing }
        return outgoing.count == 1 && outgoing[0].isText && !outgoing[0].deliveryFailed &&
            matches(expected: expected, observed: outgoing[0].text, ocr: ocr)
    }
}
