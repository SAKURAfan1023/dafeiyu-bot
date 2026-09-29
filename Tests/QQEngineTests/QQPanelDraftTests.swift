import Foundation
import Testing
import BotCore
@testable import WeChatAIBot

@Suite @MainActor struct QQPanelDraftTests {
    @Test func editingDoesNotMutateRuntimeAndUnrelatedSettingsDoNotConflict() throws {
        let engine = QQEngine(preview: true, allowAuthenticationUI: false)
        let original = engine.config
        var reply = QQPanelDraft(value: QQReplyForm(original))
        reply.value.ai.dailyLimit = 17
        reply.value.memoryEnabled = true
        reply.value.persona.maxCharacters = 42
        #expect(reply.hasChanges)
        #expect(engine.config == original)
        var updated = original
        updated.effectiveImageGeneration.enabled = true
        reply.refresh(QQReplyForm(updated))
        #expect(!reply.conflicts(with: QQReplyForm(updated)))
        #expect(reply.value.ai.dailyLimit == 17 && reply.value.memoryEnabled)
        updated.ai.dailyLimit = 31
        reply.refresh(QQReplyForm(updated))
        #expect(reply.conflicts(with: QQReplyForm(updated)))
        #expect(reply.value.ai.dailyLimit == 17)
        reply.reset(QQReplyForm(updated))
        #expect(!reply.hasChanges && reply.value.ai.dailyLimit == 31)
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
        editor.replyDraft.value.ai.dailyLimit = 17
        editor.artworkDraft.value.artists = "12345,67890"
        editor.artworkDraft.value.settings.scheduleMinute = 19
        editor.imageZhipuKey = "synthetic-test-input"
        // The actual QQ page's onAppear invokes refresh; the window keeps editor.
        editor.refresh(config)
        #expect(editor.replyDraft.value.ai.dailyLimit == 17)
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
        #expect(editor.replyDraft.value.ai.dailyLimit == 17)
    }

}
