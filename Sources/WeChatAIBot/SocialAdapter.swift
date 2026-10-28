import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SocialIdentity: Codable { var id: String; var name: String }
struct SocialWriteResult: Codable { var state: String; var externalID: String?; var authorID: String?; var reason: String?; var restricted: Bool? }
@MainActor protocol SocialAdapter: AnyObject {
    func login() async throws -> String
    func identity() async throws -> SocialIdentity
    func search(_ keyword: String) async throws -> [SocialCandidate]
    func read(_ id: String) async throws -> SocialPost
    func submit(_ record: SocialRecord) async throws -> SocialWriteResult
    func verify(_ record: SocialRecord) async throws -> SocialWriteResult
    func cancelPending()
    func close()
    func resetRestriction() async throws
}
extension SocialAdapter { func resetRestriction() async throws {} }

/// Owns a single child and Chrome profile. Only fixed JSON operations cross this boundary.
@MainActor final class SocialBrowserAdapter: SocialAdapter {
    private var child: Process?
    private var input: Pipe?
    private var endpoint: URL?
    private let token = UUID().uuidString + UUID().uuidString
    private let directory: URL
    private let platform: SocialPlatform
    private var locators: [String: String] = [:]
    init(directory: URL, platform: SocialPlatform) { self.directory = directory; self.platform = platform }
    private func start() async throws {
        if let child, child.isRunning, endpoint != nil { return }
        guard child == nil else { throw AppFailure.message("\(platform.name)执行器已中断，请关闭客户端后重新打开；未知发送记录仍保留") }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dependencies = ProcessInfo.processInfo.environment["DAFEIYU_XHS_RUNTIME_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/share/dafeiyu/xhs-runtime")
        let resources = RuntimeResources.directory?.appendingPathComponent("SocialBrowser/browser.mjs")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/SocialBrowser/browser.mjs")
        let installedNode = (try? String(contentsOf: dependencies.appendingPathComponent("node-path")))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nodes = [installedNode, home.appendingPathComponent(".local/bin/node").path, "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        guard let node = nodes.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              FileManager.default.fileExists(atPath: dependencies.appendingPathComponent("node_modules/playwright-core/package.json").path),
              FileManager.default.fileExists(atPath: resources.path) else {
            throw AppFailure.message("请先运行 bash scripts/setup-social.sh 安装浏览器依赖（需要 Node 20+ 和 Chrome）")
        }
        let process = Process(), stdout = Pipe(), stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: node); process.arguments = [resources.path]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": home.path,
            "DAFEIYU_XHS_TOKEN": token, "DAFEIYU_XHS_PROFILE": directory.appendingPathComponent("browser-profile").path,
            "DAFEIYU_XHS_DEPENDENCIES": dependencies.path, "DAFEIYU_SOCIAL_PLATFORM": platform.rawValue]
        #if os(Linux)
        for name in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "XAUTHORITY"] {
            if let value = ProcessInfo.processInfo.environment[name] { process.environment?[name] = value }
        }
        #endif
        process.standardOutput = stdout; process.standardError = FileHandle.nullDevice; process.standardInput = stdin
        try process.run(); child = process; input = stdin
        try? stdout.fileHandleForWriting.close()
        let startupDeadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: startupDeadline)
        defer { startupDeadline.cancel() }
        // No browser is launched until login/read is explicitly requested.
        let handle = stdout.fileHandleForReading
        let data: Data = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: handle.availableData) }
        }
        guard data.count < 1024, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Int],
              let port = object["port"], (1...65535).contains(port) else { close(); throw AppFailure.message("\(platform.name)执行器未能启动") }
        endpoint = URL(string: "http://127.0.0.1:\(port)/action")
    }
    private func call<T: Decodable>(_ action: String, fields: [String: Any] = [:], as type: T.Type) async throws -> T {
        try await start()
        var request = URLRequest(url: endpoint!); request.httpMethod = "POST"; request.timeoutInterval = 55
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var object = fields; object["action"] = action
        request.httpBody = try JSONSerialization.data(withJSONObject: object)
        do {
            let (data, response) = try await URLSession.shared.boundedData(for: request, limit: 2_000_000)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                let code = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "page_unavailable"
                if code == "platform_restricted" { throw SocialAccessFailure.restricted }
                let messages = ["login_required":"请先在独立浏览器登录小红书", "login_button_missing":"登录入口未加载，请检查独立浏览器", "login_qr_missing":"登录二维码未加载，请重新打开登录窗口", "browser_missing":"未找到 Chrome/Chromium，请先安装浏览器", "account_changed":"账号发生变化，已阻止发送", "target_missing":"目标评论未加载，已阻止发送", "operation_timeout":"页面操作超时，浏览器会话已关闭", "page_unavailable":"页面结构变化或访问受限，请在独立浏览器检查"]
                throw AppFailure.message((messages[code] ?? "平台操作未完成，请检查浏览器").replacingOccurrences(of: "小红书", with: platform.name))
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as SocialAccessFailure { throw error }
        catch let error as AppFailure { throw error }
        catch {
            // Transport loss does not mean the browser stopped. Freeze until process closure.
            close(); throw AppFailure.message("执行器通信中断；可能已发出的回复不会重试，请重启后核对记录")
        }
    }
    func login() async throws -> String {
        struct Response: Decodable { var qr: String }
        return try await call("login", as: Response.self).qr
    }
    func identity() async throws -> SocialIdentity { try await call("identity", as: SocialIdentity.self) }
    func search(_ keyword: String) async throws -> [SocialCandidate] {
        struct Item: Decodable { var id: String; var locator: String; var title: String; var author: String; var kind: String }
        struct Response: Decodable { var posts: [Item] }
        let response = try await call("search", fields: ["keyword": keyword], as: Response.self)
        locators = Dictionary(response.posts.map { ($0.id, $0.locator) }, uniquingKeysWith: { first, _ in first })
        return response.posts.map { SocialCandidate(id: $0.id, title: $0.title, author: $0.author, kind: $0.kind) }
    }
    func read(_ id: String) async throws -> SocialPost {
        guard let locator = locators[id] else { throw AppFailure.message("读取凭据已过期，请重新搜索该帖子") }
        return try await call("read", fields: ["id": id, "locator": locator], as: SocialPost.self)
    }
    private func fields(_ record: SocialRecord) throws -> [String: Any] {
        guard let locator = locators[record.post.id] else { throw AppFailure.message("请重新搜索原帖，恢复只读定位后再核对") }
        return ["id": record.post.id, "locator": locator, "content": record.text, "expectedUID": record.accountID,
                "parentID": record.parentID ?? "", "externalID": record.externalID ?? "", "fingerprint": record.fingerprint,
                "deadline": (record.expiresAt?.timeIntervalSince1970 ?? 0) * 1000]
    }
    func submit(_ record: SocialRecord) async throws -> SocialWriteResult {
        return try await call("submit", fields: fields(record), as: SocialWriteResult.self)
    }
    func verify(_ record: SocialRecord) async throws -> SocialWriteResult {
        return try await call("verify", fields: fields(record), as: SocialWriteResult.self)
    }
    func cancelPending() {
        guard let endpoint else { return }
        var request = URLRequest(url: endpoint.deletingLastPathComponent().appendingPathComponent("cancel"))
        request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        Task { _ = try? await URLSession.shared.boundedData(for: request, limit: 2048) }
    }
    func resetRestriction() async throws {
        struct Response: Decodable {}
        let _: Response = try await call("resetRestriction", as: Response.self)
    }
    func close() {
        endpoint = nil; locators = [:]; try? input?.fileHandleForWriting.close(); input = nil
        if let child, child.isRunning { child.terminate() }
        // A closed adapter cannot restart and overlap its old Chrome process.
    }
    deinit { if let child, child.isRunning { child.terminate() } }
}
