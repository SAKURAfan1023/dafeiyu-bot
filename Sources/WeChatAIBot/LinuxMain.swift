#if os(Linux)
import Foundation
import Glibc

@main struct LinuxMain {
    @MainActor static func main() async {
        setbuf(stdout, nil)
        umask(0o077)
        do {
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
