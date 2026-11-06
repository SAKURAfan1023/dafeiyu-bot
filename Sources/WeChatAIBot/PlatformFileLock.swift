import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Keep replacement atomic and private when Windows readers briefly deny delete sharing.
func writePrivateData(_ data: Data, to file: URL, options: Data.WritingOptions = .atomic) throws {
    #if os(Windows)
    let temporary = file.deletingLastPathComponent().appendingPathComponent(".dafeiyu-" + UUID().uuidString + ".tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try data.write(to: temporary, options: .withoutOverwriting)
    try protectWindowsFile(temporary)
    let deadline = DispatchTime.now() + .seconds(1)
    while true {
        let result = temporary.path.withCString(encodedAs: UTF16.self) { source in
            file.path.withCString(encodedAs: UTF16.self) { destination in
                let success = MoveFileExW(source, destination, DWORD(MOVEFILE_REPLACE_EXISTING) | DWORD(MOVEFILE_WRITE_THROUGH))
                return (success: success, error: success ? DWORD(ERROR_SUCCESS) : GetLastError())
            }
        }
        if result.success { return }
        let code = result.error
        guard (code == DWORD(ERROR_SHARING_VIOLATION) || code == DWORD(ERROR_LOCK_VIOLATION)), DispatchTime.now() < deadline else {
            throw AppFailure.message("无法原子更新本机数据（Windows \(code)）")
        }
        // Retry only the same local rename, never a QQ submission or model request.
        Thread.sleep(forTimeInterval: 0.02)
    }
    #else
    try data.write(to: file, options: options)
    try protectPrivateFile(file)
    #endif
}

/// The OS owns the lock: process exit releases it without deleting another owner's lock file.
final class PlatformFileLock {
    #if os(Windows)
    private let handle: HANDLE
    #else
    private let descriptor: Int32
    #endif

    init(url: URL, message: String) throws {
        #if os(Windows)
        let handle = url.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw AppFailure.message(message) }
        self.handle = handle
        #else
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw AppFailure.message("无法创建运行锁") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw AppFailure.message(message) }
        self.descriptor = descriptor
        #endif
    }

    deinit {
        #if os(Windows)
        CloseHandle(handle)
        #else
        _ = flock(descriptor, LOCK_UN); close(descriptor)
        #endif
    }
}

/// Atomic replacements need permissions applied again; Windows uses a protected user SID ACL.
func protectPrivateFile(_ file: URL) throws {
    #if os(Windows)
    try protectWindowsFile(file)
    #else
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    #endif
}

func createPrivateDirectory(_ directory: URL, intermediates: Bool = true) throws {
    #if os(Windows)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: intermediates)
    try protectWindowsFile(directory)
    #else
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: intermediates, attributes: [.posixPermissions: 0o700])
    #endif
}
