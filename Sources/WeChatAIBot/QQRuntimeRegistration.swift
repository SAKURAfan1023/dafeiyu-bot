import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A private discovery record, backed by an OS lease; not another store of QQ account data.
final class QQRuntimeRegistration {
    static let version = "0.3.0-preview.2"
    struct Record: Codable {
        var schema = 1
        var module = "qq"
        var version = QQRuntimeRegistration.version
        var generation: String
        var pid: Int32
        var controlURL: String
    }
    private let lease: PlatformFileLock
    private let file: URL
    private let generation: String
    @MainActor init(server: QQControlServer, directory: URL) throws {
        lease = try PlatformFileLock(url: directory.appendingPathComponent("qq-worker.lock"), message: "已有 QQ 后台，请连接现有实例")
        file = directory.appendingPathComponent("qq-worker.json"); generation = server.generation
        let record = Record(generation: generation, pid: ProcessInfo.processInfo.processIdentifier, controlURL: server.controlURL.absoluteString)
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
        try protectPrivateFile(file)
    }
    static func existingURL(directory: URL) -> URL? {
        let file = directory.appendingPathComponent("qq-worker.json")
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
              let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schema == 1, record.module == "qq", record.version == version, record.pid > 0,
              let url = URL(string: record.controlURL), url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
              url.user == nil, url.password == nil, url.query == nil, url.path == "/", url.fragment?.count == 72 else { return nil }
        #if os(Windows)
        guard let handle = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(record.pid)) else { return nil }
        defer { CloseHandle(handle) }
        var status: DWORD = 0
        guard GetExitCodeProcess(handle, &status), status == DWORD(STILL_ACTIVE) else { return nil }
        #else
        guard kill(record.pid, 0) == 0 else { return nil }
        #endif
        return url
    }
    deinit {
        if let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(Record.self, from: data), record.generation == generation {
            try? FileManager.default.removeItem(at: file)
        }
        withExtendedLifetime(lease) {}
    }
}

#if os(Windows)
func protectWindowsFile(_ file: URL) throws {
    var token: HANDLE?
    guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else {
        throw AppFailure.message("无法核对 Windows 用户权限")
    }
    defer { CloseHandle(token) }
    var size: DWORD = 0
    _ = GetTokenInformation(token, TokenUser, nil, 0, &size)
    guard size > 0 else { throw AppFailure.message("无法读取 Windows 用户身份") }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<TOKEN_USER>.alignment)
    defer { buffer.deallocate() }
    guard GetTokenInformation(token, TokenUser, buffer, size, &size) else { throw AppFailure.message("无法读取 Windows 用户身份") }
    var owner: PSID?
    var existing: PSECURITY_DESCRIPTOR?
    let owned = file.path.withCString(encodedAs: UTF16.self) { path in
        GetNamedSecurityInfoW(UnsafeMutablePointer(mutating: path), SE_FILE_OBJECT, DWORD(OWNER_SECURITY_INFORMATION),
                             &owner, nil, nil, nil, &existing) == DWORD(ERROR_SUCCESS)
    }
    defer { if let existing { _ = LocalFree(existing) } }
    // Elevated Windows processes may create files owned by the Administrators group.
    guard owned, let owner,
          EqualSid(owner, buffer.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid) || IsWellKnownSid(owner, WinBuiltinAdministratorsSid) else {
        throw AppFailure.message("数据位置必须归当前 Windows 用户所有")
    }
    var sid: LPWSTR?
    guard ConvertSidToStringSidW(buffer.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid, &sid), let sid else {
        throw AppFailure.message("无法读取 Windows 用户标识")
    }
    defer { _ = LocalFree(sid) }
    let acl = "D:P(A;OICI;FA;;;" + String(decodingCString: sid, as: UTF16.self) + ")"
    var descriptor: PSECURITY_DESCRIPTOR?
    guard acl.withCString(encodedAs: UTF16.self, { ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil) }), let descriptor else {
        throw AppFailure.message("无法建立本机私有权限")
    }
    defer { _ = LocalFree(descriptor) }
    let protected = file.path.withCString(encodedAs: UTF16.self) {
        SetFileSecurityW($0, DWORD(DACL_SECURITY_INFORMATION) | DWORD(PROTECTED_DACL_SECURITY_INFORMATION), descriptor)
    }
    guard protected else { throw AppFailure.message("无法保护本机数据，已停止操作") }
}
#endif
