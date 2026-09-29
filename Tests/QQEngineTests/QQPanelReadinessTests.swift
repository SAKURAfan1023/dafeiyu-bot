import Foundation
import Testing
import BotCore
@testable import WeChatAIBot

@Suite @MainActor struct QQPanelReadinessTests {
    @Test func disabledFeaturesDoNotProduceCredentialWarnings() {
        let engine = QQEngine(preview: true, allowAuthenticationUI: false)
        #expect(engine.configurationHints.isEmpty)
        engine.config.effectiveVisualTools.googleWebEnabled = true
        let hints = engine.configurationHints.joined(separator: "\n")
        #expect(hints.contains("启用识图") && hints.contains("联网开关未启用"))
        #expect(hints.contains("Google 搜图凭证当前未载入"))
        #expect(!hints.contains("Cloudflare"))
    }

    @Test func loadedCredentialsAndSavedSwitchesResolveToolDependencies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        engine.save(expectedSelfID: "12345")
        try #require(engine.error == nil, "\(engine.error ?? "")")
        var visual = QQVisualConfig(); visual.provider = .zhipu; visual.googleWebEnabled = true
        engine.saveVisualTools(visual, googleKey: "synthetic-google", persistCredentials: false)
        try #require(engine.error == nil, "\(engine.error ?? "")")
        engine.config.effectiveVisionEnabled = true; engine.config.effectiveOnlineEnabled = true
        var image = QQImageGenerationConfig(); image.enabled = true; image.fallbackEnabled = false
        engine.saveImageGeneration(image, zhipuKey: "synthetic-zhipu", cloudflareToken: "", persistCredentials: false)
        try #require(engine.error == nil, "\(engine.error ?? "")")
        #expect(engine.configurationHints.isEmpty)
        image.fallbackEnabled = true
        engine.saveImageGeneration(image, zhipuKey: "", cloudflareToken: "", persistCredentials: false)
        try #require(engine.error == nil, "\(engine.error ?? "")")
        #expect(engine.configurationHints.contains { $0.contains("Account ID") })
        #expect(engine.configurationHints.contains { $0.contains("Cloudflare 生图凭证当前未载入") })
        image.cloudflareAccountID = String(repeating: "a", count: 32)
        engine.saveImageGeneration(image, zhipuKey: "", cloudflareToken: "synthetic-cloudflare", persistCredentials: false)
        try #require(engine.error == nil, "\(engine.error ?? "")")
        #expect(engine.configurationHints.isEmpty)
        #expect(!engine.running && engine.sends.attempts == 0)
    }

    @Test func scheduleAndParticipationRequireEnabledTargets() {
        let engine = QQEngine(preview: true, allowAuthenticationUI: false)
        engine.config.effectiveArtwork.scheduleEnabled = true
        engine.config.effectiveGroupParticipationEnabled = true
        #expect(engine.configurationHints.contains { $0.contains("插画功能未启用") })
        #expect(engine.configurationHints.contains { $0.contains("没有已启用的目标") })
        #expect(engine.configurationHints.contains { $0.contains("没有已启用的群") })
        var group = QQTarget(number: "99999", name: "合成群", group: true); group.enabled = true
        let friend = QQTarget(number: "54321", name: "合成好友", group: false)
        engine.config.targets = [group, friend]
        engine.config.effectiveArtwork.enabled = true
        engine.config.effectiveArtwork.scheduleTargets = [group.key, friend.key]
        #expect(engine.configurationHints.count == 1)
        #expect(engine.configurationHints[0].contains("部分定时目标"))
        engine.config.targets[1].enabled = true
        #expect(engine.configurationHints.isEmpty)
    }
}
