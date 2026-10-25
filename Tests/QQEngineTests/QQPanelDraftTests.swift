import Foundation
import Testing
import BotCore
@testable import WeChatAIBot

@Suite @MainActor struct QQPanelDraftTests {
    @Test func firstPaintWebDefaultsMatchNativeSettings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let html = try String(contentsOf: root.appendingPathComponent("Resources/QQControl/index.html"), encoding: .utf8)
        let config = QQConfig(), persona = QQPersona(), memory = QQMemoryOptions(), art = QQArtworkConfig(), limits = SendLimits()
        let values = ["maxCharacters": persona.maxCharacters, "stickerEveryReplies": persona.effectiveStickerEveryReplies,
                      "stickerIntervalSeconds": persona.stickerIntervalSeconds, "groupParticipationEvery": config.effectiveGroupParticipationEvery,
                      "daily": config.ai.dailyLimit, "cooldown": config.ai.cooldownSeconds, "sendDaily": limits.daily,
                      "chatDaily": limits.perChatDaily, "globalInterval": limits.globalIntervalSeconds,
                      "workStart": config.ai.workStart, "workEnd": config.ai.workEnd,
                      "memoryMessages": memory.messageThreshold, "memoryCharacters": memory.characterThreshold,
                      "memoryMinutes": memory.intervalMinutes, "memoryBudget": memory.retrievalCharacters,
                      "artDaily": art.dailyPerChat, "artNetwork": art.networkDailyLimit, "artRepeat": art.repeatDays,
                      "artBookmarks": art.effectiveSearchMinBookmarks, "artLong": art.minLongEdge, "artShort": art.minShortEdge,
                      "artHour": art.scheduleHour, "artMinute": art.scheduleMinute]
        for (id, value) in values {
            let pattern = "<input\\b[^>]*\\bid=\"\(id)\"[^>]*\\bvalue=\"\(value)\""
            #expect(html.range(of: pattern, options: .regularExpression) != nil, "Missing or mismatched default: \(id)")
        }
        #expect(html.contains("<option value=\"teasing\" selected>\(persona.effectiveStyle.name)</option>"))
        #expect(html.contains("<option value=\"\(persona.banter)\" selected>"))
        #expect(html.contains("id=\"stickersEnabled\" type=\"checkbox\" checked"))
        #expect(html.contains("value=\"\(config.ai.model)\""))
        #expect(html.contains("value=\"\(config.endpoint)\""))
        #expect(html.contains("<textarea id=\"prompt\">\(config.ai.prompt)</textarea>"))
    }

    @Test(arguments: ["范围与回复", "记忆与记录", "插画与定时", "AI 生图", "识图与搜图"])
    func recommendedSettingsOnlyChangeCurrentPageDraft(_ section: String) throws {
        var config = QQConfig()
        config.expectedSelfID = "12345"
        config.targets = [QQTarget(number: "54321", name: "synthetic friend", group: false)]
        config.targets[0].enabled = true; config.targets[0].personaStyle = .gentle
        config.ai.dailyLimit = 999; config.ai.maxTokens = 950
        config.effectivePersona.maxCharacters = 88
        config.memoryEnabled = true; config.effectiveMemoryOptions.messageThreshold = 99
        config.effectiveArtwork.networkDailyLimit = 450
        config.effectiveArtwork.pixivArtistIDs = ["54321"]
        config.effectiveArtwork.scheduleTargets = ["private:54321"]
        config.effectiveImageGeneration.enabled = true
        config.effectiveImageGeneration.cloudflareAccountID = String(repeating: "a", count: 32)
        config.effectiveVisualTools.googleWebEnabled = true
        var editor = QQPanelState(); editor.refresh(config)
        editor.section = ["范围与回复", "记忆与记录"].contains(section) ? section : "图片与工具"
        editor.toolSection = section
        editor.token = "synthetic-token-input"; editor.temporaryKey = "synthetic-key-input"
        editor.imageZhipuKey = "synthetic-image-input"; editor.googleVisionKey = "synthetic-google-input"
        editor.artworkDraft.value.artists = "24680"
        editor.useRecommendedSettings()
        #expect(editor.connectionDraft.value == QQConnectionForm(config))
        #expect(editor.replyDraft.value.targets == config.targets)
        #expect(editor.replyDraft.baseline == QQReplyForm(config))
        #expect(editor.artworkDraft.baseline == QQArtworkForm(config.effectiveArtwork))
        #expect(editor.imageDraft.baseline == config.effectiveImageGeneration)
        #expect(editor.visualDraft.baseline == config.effectiveVisualTools)
        #expect(editor.imageDraft.value.cloudflareAccountID == config.effectiveImageGeneration.cloudflareAccountID)
        #expect(editor.token == "synthetic-token-input" && editor.temporaryKey == "synthetic-key-input")
        #expect(editor.imageZhipuKey == "synthetic-image-input" && editor.googleVisionKey == "synthetic-google-input")
        #expect(editor.artworkDraft.value.artists == "24680")
        #expect(editor.artworkDraft.value.settings.scheduleTargets == config.effectiveArtwork.scheduleTargets)
        switch section {
        case "范围与回复":
            #expect(editor.replyDraft.value.persona == QQPersona())
            #expect(editor.replyDraft.value.dailyLimit == String(QQConfig().ai.dailyLimit))
            #expect(editor.replyDraft.value.ai.maxTokens == 950)
            #expect(editor.replyDraft.value.memoryEnabled && editor.replyDraft.value.memoryOptions == config.effectiveMemoryOptions)
        case "记忆与记录":
            #expect(editor.replyDraft.value.memoryOptions == QQMemoryOptions())
            #expect(editor.replyDraft.value.persona == config.effectivePersona)
        case "插画与定时": #expect(try editor.artworkDraft.value.validatedSettings().networkDailyLimit == QQArtworkConfig().networkDailyLimit)
        case "AI 生图": #expect(!editor.imageDraft.value.enabled)
        default: #expect(editor.visualDraft.value == QQVisualConfig())
        }
    }

    @Test func replyLimitTextKeepsInvalidDraftAndPersistsAllCorrectedFieldsTogether() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        engine.save(expectedSelfID: "12345")
        try #require(engine.error == nil)
        let before = engine.config
        var draft = QQPanelDraft(value: QQReplyForm(before))
        draft.value.dailyLimit = "1000"; draft.value.sendDaily = ""; draft.value.perChatDaily = "1000"
        draft.value.persona.maxCharacters = 42
        draft.refresh(QQReplyForm(before))
        #expect(draft.hasChanges && draft.value.sendDaily.isEmpty)
        #expect(throws: (any Error).self) {
            try engine.saveReplySettings(ai: draft.value.validatedAI(), persona: draft.value.persona)
        }
        #expect(engine.config == before)
        #expect(QQEngine(allowAuthenticationUI: false, storageDirectory: directory).config == before)
        draft.value.sendDaily = " 1000 "
        engine.saveReplySettings(ai: try draft.value.validatedAI(), persona: draft.value.persona)
        try #require(engine.error == nil)
        draft.reset(QQReplyForm(engine.config))
        #expect(!draft.hasChanges && draft.value.sendDaily == "1000")
        let saved = QQEngine(allowAuthenticationUI: false, storageDirectory: directory).config
        #expect(saved.ai.dailyLimit == 1000 && saved.ai.effectiveSendLimits.daily == 1000)
        #expect(saved.ai.effectiveSendLimits.perChatDaily == 1000 && saved.effectivePersona.maxCharacters == 42)
        #expect(!engine.running && engine.usage.calls == 0 && engine.sends.attempts == 0)
    }

    @Test func replyLimitTextRejectsMalformedValuesAndRetainsOtherAISettings() throws {
        var config = QQConfig()
        config.ai.prompt = "synthetic preference"
        config.ai.cooldownSeconds = 7
        config.ai.effectiveSendLimits.globalIntervalSeconds = 9
        let fields: [WritableKeyPath<QQReplyForm, String>] = [\.dailyLimit, \.sendDaily, \.perChatDaily]
        for field in fields {
            for raw in ["", "0", "10001", "1.5", "-1", "1e3", String(repeating: "9", count: 50)] {
                var form = QQReplyForm(config); form[keyPath: field] = raw
                #expect(throws: (any Error).self) { try form.validatedAI() }
                #expect(form[keyPath: field] == raw)
            }
        }
        var form = QQReplyForm(config)
        form.dailyLimit = "1"; form.sendDaily = "10000"; form.perChatDaily = " 1000 "
        let result = try form.validatedAI()
        #expect(result.dailyLimit == 1 && result.effectiveSendLimits.daily == 10000)
        #expect(result.effectiveSendLimits.perChatDaily == 1000)
        #expect(result.prompt == config.ai.prompt && result.cooldownSeconds == 7)
        #expect(result.effectiveSendLimits.globalIntervalSeconds == 9)
    }

    @Test func artworkTextDraftValidatesBeforePersistingAndSurvivesRefresh() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = QQEngine(allowAuthenticationUI: false, storageDirectory: directory)
        engine.save(expectedSelfID: "12345")
        let before = engine.config
        var draft = QQPanelDraft(value: QQArtworkForm(before.effectiveArtwork))
        draft.value.networkDailyLimit = ""
        draft.value.searchMinBookmarks = "1200.5"
        draft.refresh(QQArtworkForm(before.effectiveArtwork))
        #expect(draft.value.networkDailyLimit.isEmpty && draft.value.searchMinBookmarks == "1200.5")
        #expect(draft.hasChanges)
        #expect(throws: (any Error).self) { try engine.saveArtwork(draft.value.validatedSettings()) }
        #expect(engine.config == before)
        #expect(QQEngine(allowAuthenticationUI: false, storageDirectory: directory).config == before)
        draft.value.networkDailyLimit = " 450 "
        #expect(throws: (any Error).self) { try draft.value.validatedSettings() }
        draft.value.searchMinBookmarks = "1200"
        draft.value.minLongEdge = "0"; draft.value.minShortEdge = "0"
        engine.saveArtwork(try draft.value.validatedSettings())
        try #require(engine.error == nil)
        draft.reset(QQArtworkForm(engine.config.effectiveArtwork))
        #expect(!draft.hasChanges && draft.value.networkDailyLimit == "450")
        let saved = QQEngine(allowAuthenticationUI: false, storageDirectory: directory).config.effectiveArtwork
        #expect(saved.networkDailyLimit == 450 && saved.effectiveSearchMinBookmarks == 1200)
        #expect(saved.minLongEdge == 0 && saved.minShortEdge == 0)
        #expect(!engine.running && engine.usage.calls == 0 && engine.sends.attempts == 0)
    }

    @Test func artworkTextDraftRejectsMalformedAndOutOfRangeNumbers() {
        var form = QQArtworkForm(QQArtworkConfig())
        form.minLongEdge = "1e3"
        #expect(throws: (any Error).self) { try form.validatedSettings() }
        form.minLongEdge = "1400"; form.minShortEdge = "-1"
        #expect(throws: (any Error).self) { try form.validatedSettings() }
        form.minShortEdge = "720"; form.networkDailyLimit = "2001"
        #expect(throws: (any Error).self) { try form.validatedSettings() }
        form.networkDailyLimit = "300"; form.searchMinBookmarks = String(repeating: "9", count: 50)
        #expect(throws: (any Error).self) { try form.validatedSettings() }
    }

    @Test func editingDoesNotMutateRuntimeAndUnrelatedSettingsDoNotConflict() throws {
        let engine = QQEngine(preview: true, allowAuthenticationUI: false)
        let original = engine.config
        var reply = QQPanelDraft(value: QQReplyForm(original))
        reply.value.dailyLimit = "17"
        reply.value.memoryEnabled = true
        reply.value.persona.maxCharacters = 42
        #expect(reply.hasChanges)
        #expect(engine.config == original)
        var updated = original
        updated.effectiveImageGeneration.enabled = true
        reply.refresh(QQReplyForm(updated))
        #expect(!reply.conflicts(with: QQReplyForm(updated)))
        #expect(reply.value.dailyLimit == "17" && reply.value.memoryEnabled)
        updated.ai.dailyLimit = 31
        reply.refresh(QQReplyForm(updated))
        #expect(reply.conflicts(with: QQReplyForm(updated)))
        #expect(reply.value.dailyLimit == "17")
        reply.reset(QQReplyForm(updated))
        #expect(!reply.hasChanges && reply.value.dailyLimit == "31")
    }

    @Test func cleanDraftTracksExternalChangesAndSuccessfulSaveClearsDirty() {
        var config = QQConfig()
        var connection = QQPanelDraft(value: QQConnectionForm(config))
        config.endpoint = "ws://127.0.0.1:3101"
        connection.refresh(QQConnectionForm(config))
        #expect(connection.value.endpoint == config.endpoint && !connection.hasChanges)
        connection.value.expectedSelfID = "12345"
        #expect(config.expectedSelfID.isEmpty)
        config.expectedSelfID = "12345"
        connection.refresh(QQConnectionForm(config))
        #expect(!connection.hasChanges)
        var image = QQPanelDraft(value: QQImageGenerationConfig())
        image.value.enabled = true
        #expect(!config.effectiveImageGeneration.enabled)
        config.effectiveImageGeneration = image.value
        image.refresh(config.effectiveImageGeneration)
        #expect(!image.hasChanges)
    }
    @Test func windowOwnedDraftsSurvivePageReentryAndTrackOnlyCleanExternalUpdates() {
        var config = QQConfig()
        config.expectedSelfID = "12345"
        var editor = QQPanelState()
        editor.refresh(config)
        editor.replyDraft.value.dailyLimit = "17"
        editor.artworkDraft.value.artists = "12345,67890"
        editor.artworkDraft.value.settings.scheduleMinute = 19
        editor.imageZhipuKey = "synthetic-test-input"
        // The actual QQ page's onAppear invokes refresh; the window keeps editor.
        editor.refresh(config)
        #expect(editor.replyDraft.value.dailyLimit == "17")
        #expect(editor.artworkDraft.value.artists == "12345,67890")
        #expect(editor.artworkDraft.value.settings.scheduleMinute == 19)
        #expect(editor.hasCredentialDrafts)
        #expect(editor.imageZhipuKey == "synthetic-test-input")
        config.effectiveImageGeneration.fallbackEnabled.toggle()
        editor.refresh(config)
        #expect(editor.imageDraft.value == config.effectiveImageGeneration)
        #expect(!editor.artworkDraft.conflicts(with: QQArtworkForm(config.effectiveArtwork)))
        // A roster update may not silently replace a pending batch edit.
        config.effectiveArtwork.pixivArtistIDs = ["24680"]
        editor.refresh(config)
        #expect(editor.artworkDraft.value.artists == "12345,67890")
        #expect(editor.artworkDraft.conflicts(with: QQArtworkForm(config.effectiveArtwork)))
        editor.artworkDraft.reset(QQArtworkForm(config.effectiveArtwork))
        #expect(editor.artworkDraft.value.artists == "24680")
        #expect(!editor.artworkDraft.hasChanges)
        #expect(editor.replyDraft.value.dailyLimit == "17")
    }

}
