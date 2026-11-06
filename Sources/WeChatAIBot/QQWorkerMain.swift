#if DAFEIYU_QQ_ONLY
import Foundation
#if os(Windows)
import ucrt
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import BotCore

@main struct QQWorkerMain {
    @MainActor static func main() async {
        #if !os(Windows)
        umask(0o077)
        #endif
        do {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--qq-check"), args.indices.contains(i + 2) {
                var config = QQConfig(); config.endpoint = args[i + 1]; config.expectedSelfID = args[i + 2]; try config.validate()
                let connection = OneBotConnection(); defer { connection.close() }
                try await connection.connect(endpoint: config.endpoint, token: readLine() ?? "")
                async let login = connection.action("get_login_info")
                async let health = connection.action("get_status")
                let (a, b) = try await (login, health)
                guard let account = a["data"] as? [String: Any], QQPolicy.identifier(account["user_id"]) == config.expectedSelfID,
                      let status = b["data"] as? [String: Any], status["online"] as? Bool == true, status["good"] as? Bool == true else {
                    throw AppFailure.message("QQ 账号或在线状态未通过核对")
                }
                print("QQ 账号与在线状态核对成功；未读取聊天或发送消息"); return
            }
            let directory = try LocalStore().directory
            #if os(Windows)
            try protectWindowsFile(directory)
            #endif
            let engine = QQEngine(allowAuthenticationUI: false)
            let server = try QQControlServer(engine: engine)
            let registration = try QQRuntimeRegistration(server: server, directory: directory)
            defer { engine.disconnect(); server.stop(); withExtendedLifetime(registration) {} }
            server.start(announce: false)
            if !args.contains("--quiet") {
                FileHandle.standardOutput.write(Data("QQ_CONTROL_URL=\(server.controlURL.absoluteString)\n".utf8))
            }
            while !Task.isCancelled, !server.workerStopRequested { try await Task.sleep(nanoseconds: 200_000_000) }
            // Let the final HTTP response drain before revoking clients and the discovery record.
            try await Task.sleep(nanoseconds: 200_000_000)
        } catch {
            // Do not serialize local addresses, credentials or provider response bodies to launcher logs.
            FileHandle.standardError.write(Data("QQ 后台启动或检查失败，请检查依赖、账号及运行锁\n".utf8)); exit(1)
        }
    }
}
#endif
