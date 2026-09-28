import Foundation

enum RuntimeResources {
    static var supportsKeychain: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
    static var directory: URL? {
        #if os(Linux)
        if let path = ProcessInfo.processInfo.environment["DAFEIYU_RESOURCES"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true)
        #else
        return Bundle.main.resourceURL
        #endif
    }
}
