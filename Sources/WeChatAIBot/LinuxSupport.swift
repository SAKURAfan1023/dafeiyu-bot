#if os(Linux) || os(Windows)
import Foundation
import FoundationNetworking
#if os(Windows)
import WinSDK
#endif

// Desktop observation is unused by the headless engine; all engine state still belongs to MainActor.
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

// No plaintext fallback for macOS Keychain. Linux credentials are deliberately session-only.
enum Keychain {
    static func load(account: String = "api-key", allowAuthenticationUI: Bool = true) throws -> String { "" }
    static func save(_ value: String, account: String = "api-key") throws {
        throw AppFailure.message("Windows / Linux 版仅支持本次运行凭证，请取消保存到钥匙串")
    }
}

enum LinuxImages {
    static func process(_ data: Data, mode: String, options: [String: Int] = [:]) throws -> [Data] {
        guard data.count <= 20_000_000, let resources = RuntimeResources.directory else {
            throw AppFailure.message("图片过大或资源目录不可用")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dafeiyu-image-" + UUID().uuidString)
        try createPrivateDirectory(directory, intermediates: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input"), output = directory.appendingPathComponent("output")
        let payload: [String: Any] = ["image": data.base64EncodedString(), "mode": mode, "options": options]
        try JSONSerialization.data(withJSONObject: payload).write(to: input)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let stdin = try FileHandle(forReadingFrom: input), stdout = try FileHandle(forWritingTo: output)
        defer { try? stdin.close(); try? stdout.close() }
        let process = Process()
        #if os(Windows)
        let python = ProcessInfo.processInfo.environment["DAFEIYU_PYTHON"] ?? ""
        guard !python.isEmpty, FileManager.default.isExecutableFile(atPath: python) else {
            throw AppFailure.message("请安装 Python 与 Pillow，并设置 DAFEIYU_PYTHON 为 python.exe 的完整路径")
        }
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [resources.appendingPathComponent("Linux/image-helper.py").path]
        #else
        process.executableURL = URL(fileURLWithPath: "/usr/bin/timeout")
        process.arguments = ["--signal=KILL", "20", "/usr/bin/python3", resources.appendingPathComponent("Linux/image-helper.py").path]
        #endif
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: deadline)
        process.waitUntilExit(); deadline.cancel()
        guard process.terminationStatus == 0, let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20_000_000,
              let encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String] else {
            throw AppFailure.message("图片格式、尺寸或处理时间不符合要求；请检查 Python Pillow 安装")
        }
        let images = encoded.compactMap { Data(base64Encoded: $0) }
        guard images.count == encoded.count, !images.isEmpty else { throw AppFailure.message("图片处理失败") }
        return images
    }
}
#endif
