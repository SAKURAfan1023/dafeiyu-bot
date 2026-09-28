#if os(Linux)
import Foundation
import Glibc
import BotCore

@main struct LinuxMain {
    @MainActor static func main() async {
        setbuf(stdout, nil)
        umask(0o077)
        do {
            if let index = CommandLine.arguments.firstIndex(of: "--qq-check") {
                guard CommandLine.arguments.indices.contains(index + 2) else {
                    throw AppFailure.message("用法：--qq-check 本机端点 预期账号；令牌由标准输入提供")
                }
                var config = QQConfig()
                config.endpoint = CommandLine.arguments[index + 1]
                config.expectedSelfID = CommandLine.arguments[index + 2]
                try config.validate()
                let connection = OneBotConnection()
                defer { connection.close() }
                try connection.connect(endpoint: config.endpoint, token: readLine() ?? "")
                async let login = connection.action("get_login_info")
                async let health = connection.action("get_status")
                let (a, b) = try await (login, health)
                guard let account = a["data"] as? [String: Any], QQPolicy.identifier(account["user_id"]) == config.expectedSelfID,
                      let status = b["data"] as? [String: Any], status["online"] as? Bool == true, status["good"] as? Bool == true else {
                    throw AppFailure.message("QQ 账号或在线状态未通过核对")
                }
                print("QQ 账号与在线状态核对成功；未读取聊天或发送消息")
                return
            }
            let engine = QQEngine(allowAuthenticationUI: false)
            let server = try QQControlServer(engine: engine)
            server.start()
            print("Windows / Linux 本机面板：凭证仅保存在内存，退出后需重新填写。")
            // Keep the engine and listener alive without blocking MainActor.
            defer { withExtendedLifetime(server) {} }
            while !Task.isCancelled { try await Task.sleep(nanoseconds: 60_000_000_000) }
        } catch { print("启动失败：\(error.localizedDescription)"); exit(1) }
    }
}
#endif
