import Foundation
import Testing
import BotCore
@testable import WeChatAIBot

@Suite @MainActor struct QQCredentialSaveTests {
    @Test func partialImageCredentialSaveReportsCommittedConfigAndCanRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var saved: [String: String] = [:]
        var failCloudflare = true
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, credentialWriter: { value, account in
            if account == "qq-image-cloudflare" && failCloudflare { throw AppFailure.message("合成钥匙串拒绝") }
            saved[account] = value
        })
        engine.save(expectedSelfID: "12345")
        var settings = engine.config.effectiveImageGeneration; settings.enabled = true
        let committed = engine.saveImageGeneration(settings, zhipuKey: "synthetic-zhipu-value", cloudflareToken: "synthetic-cloudflare-value", persistCredentials: true)
        #expect(committed && engine.error != nil)
        #expect(engine.hasZhipuImageKey && !engine.hasCloudflareImageToken)
        #expect(saved["qq-image-zhipu"] == "synthetic-zhipu-value" && saved["qq-image-cloudflare"] == nil)
        #expect(engine.error?.contains("已保存并载入：智谱") == true)
        #expect(engine.error?.contains("synthetic-zhipu-value") == false)
        let reopened = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(reopened.config.effectiveImageGeneration == settings)
        failCloudflare = false
        #expect(engine.saveImageGeneration(settings, zhipuKey: "synthetic-zhipu-value", cloudflareToken: "synthetic-cloudflare-value", persistCredentials: true))
        #expect(engine.error == nil && engine.hasZhipuImageKey && engine.hasCloudflareImageToken)
        let disk = try String(contentsOf: directory.appendingPathComponent("qq-state.json"), encoding: .utf8)
        #expect(!disk.contains("synthetic-zhipu-value") && !disk.contains("synthetic-cloudflare-value"))
        #expect(!engine.running && engine.sends.attempts == 0)
    }

    @Test(arguments: ["connection", "visual", "image"])
    func failedCredentialWriteKeepsCommittedSettingsAndInputsCanBeRetried(_ mode: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var reject = true
        var attempts = 0
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, credentialWriter: { _, _ in
            attempts += 1
            if reject { throw AppFailure.message("合成钥匙串拒绝") }
        })
        engine.save(expectedSelfID: "12345")
        func submit() -> Bool {
            switch mode {
            case "connection": return engine.save(token: "synthetic-token", endpoint: "ws://127.0.0.1:3101")
            case "visual":
                var settings = QQVisualConfig(); settings.provider = .zhipu
                return engine.saveVisualTools(settings, googleKey: "synthetic-google", persistCredentials: true)
            default:
                var settings = QQImageGenerationConfig(); settings.enabled = true
                return engine.saveImageGeneration(settings, zhipuKey: "synthetic-zhipu", cloudflareToken: "", persistCredentials: true)
            }
        }
        #expect(submit() && engine.error != nil && attempts == 1)
        #expect(engine.error?.contains("已保存") == true)
        #expect(!engine.hasGoogleVisionKey && !engine.hasZhipuImageKey)
        let reopened = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        #expect(reopened.config == engine.config)
        reject = false
        #expect(submit() && engine.error == nil && attempts == 2)
        #expect(!engine.running)
    }

    @Test(arguments: ["connection", "visual", "image"])
    func configurationConflictNeverTouchesCredentialStore(_ mode: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var writes = 0
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory, credentialWriter: { _, _ in writes += 1 })
        engine.save(expectedSelfID: "12345")
        let original = engine.config
        let other = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        other.save(endpoint: "ws://127.0.0.1:3102")
        let committed: Bool
        switch mode {
        case "connection": committed = engine.save(token: "synthetic-token", endpoint: "ws://127.0.0.1:3101")
        case "visual": committed = engine.saveVisualTools(QQVisualConfig(), googleKey: "synthetic-google", persistCredentials: true)
        default: committed = engine.saveImageGeneration(QQImageGenerationConfig(), zhipuKey: "synthetic-zhipu", cloudflareToken: "", persistCredentials: true)
        }
        #expect(!committed && engine.error != nil && writes == 0)
        #expect(engine.config == original)
    }
}
