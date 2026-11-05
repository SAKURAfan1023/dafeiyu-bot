import Foundation
import SwiftUI
import WebKit

@MainActor final class TestPanel: ObservableObject {
    @Published var url: URL?
    @Published var failed = false

    func load() async {
        url = nil; failed = false
        let root = Bundle.main.bundleURL.deletingLastPathComponent()
        let environment = ProcessInfo.processInfo.environment
        do {
            let controlURL = try await Task.detached(priority: .userInitiated) {
                let process = Process(), output = Pipe()
                process.executableURL = root.appendingPathComponent("runtime/node")
                process.arguments = [root.appendingPathComponent("runtime/node_modules/@sakurafan1023/cli/bin/dafeiyu.mjs").path, "qq", "status"]
                var childEnvironment = environment
                let directory = environment["DAFEIYU_MAC_TEST_DATA_DIR"].map { URL(fileURLWithPath: $0) }
                    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DaFeiYuMCPTest")
                childEnvironment["DAFEIYU_MODULES_DIR"] = root.appendingPathComponent("runtime").path
                childEnvironment["DAFEIYU_DATA_DIR"] = directory.path
                for key in ["DAFEIYU_QQ_ROOT", "DAFEIYU_RESOURCES", "DAFEIYU_NODE_DEPENDENCIES", "DAFEIYU_ONEBOT_TOKEN", "DAFEIYU_MODEL_KEY"] {
                    childEnvironment.removeValue(forKey: key)
                }
                process.environment = childEnvironment
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = output; process.standardError = FileHandle.nullDevice
                try process.run()
                try? output.fileHandleForWriting.close()
                let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: deadline)
                defer { deadline.cancel() }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0, data.count < 4_200_000,
                      let state = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let identity = state["runtime"] as? [String: Any], identity["module"] as? String == "qq" else {
                    throw URLError(.cannotConnectToHost)
                }
                let file = directory.appendingPathComponent("qq-worker.json")
                guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
                      let record = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
                      record["pid"] as? Int == identity["pid"] as? Int,
                      record["generation"] as? String == identity["generation"] as? String,
                      record["version"] as? String == identity["version"] as? String,
                      let text = record["controlURL"] as? String, let url = URL(string: text),
                      url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
                      url.path == "/", url.user == nil, url.password == nil, url.query == nil, url.fragment?.count == 72 else {
                    throw URLError(.badServerResponse)
                }
                return url
            }.value
            url = controlURL
        } catch { failed = true }
    }
}

@main struct MacQQTestApp: App {
    @StateObject private var panel = TestPanel()
    var body: some Scene {
        WindowGroup("大肥鱼 · QQ/MCP 独立测试") {
            VStack(spacing: 0) {
                HStack {
                    Text("独立测试环境").font(.headline)
                    Spacer()
                    Button("刷新连接") { Task { await panel.load() } }
                }.padding(12)
                if let url = panel.url { QQSharedPanel(url: url).id(url) }
                else if panel.failed { Text("测试后台暂不可用，请检查完整测试包后刷新连接。").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.frame(minWidth: 980, minHeight: 720).task { await panel.load() }
        }.defaultSize(width: 1160, height: 820)
    }
}
