import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
