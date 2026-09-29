import Foundation
import BotCore

/// Editors own their draft. Runtime configuration changes only after a successful save.
struct QQPanelDraft<Value: Equatable> {
    private(set) var baseline: Value
    var value: Value
    init(value: Value) { self.baseline = value; self.value = value }
    var hasChanges: Bool { value != baseline }
    func conflicts(with current: Value) -> Bool { hasChanges && baseline != current }
    mutating func refresh(_ current: Value) {
        if !hasChanges || value == current { reset(current) }
    }
    mutating func reset(_ current: Value) { baseline = current; value = current }
}

struct QQConnectionForm: Equatable {
    var endpoint: String
    var expectedSelfID: String
    init(_ config: QQConfig) { endpoint = config.endpoint; expectedSelfID = config.expectedSelfID }
}

/// Only fields saved by the reply/range editor, so changing image settings does
/// not invalidate an unrelated reply draft.
struct QQReplyForm: Equatable {
    var ai: BotConfig
    var persona: QQPersona
    var targets: [QQTarget]
    var onlineEnabled: Bool
    var visionEnabled: Bool
    var memoryEnabled: Bool
    var memoryOptions: QQMemoryOptions
    var groupParticipationEnabled: Bool
    var groupParticipationEvery: Int
    init(_ config: QQConfig) {
        ai = config.ai; persona = config.effectivePersona; targets = config.targets
        onlineEnabled = config.effectiveOnlineEnabled; visionEnabled = config.effectiveVisionEnabled
        memoryEnabled = config.effectiveMemoryEnabled; memoryOptions = config.effectiveMemoryOptions
        groupParticipationEnabled = config.effectiveGroupParticipationEnabled
        groupParticipationEvery = config.effectiveGroupParticipationEvery
    }
}

/// Owned by the dashboard window, not a conditional page. Drafts and temporary
/// credential input survive navigation, but are never serialized to disk.
struct QQPanelState {
    var token = ""
    var webToken = ""
    var temporaryKey = ""
    var search = ""
    var imageZhipuKey = ""
    var imageCloudflareToken = ""
    var persistImageCredentials = true
    var googleVisionKey = ""
    var persistVisualCredentials = true
    var durationMinutes = 120
    var section = "连接与运行"
    var connectionDraft = QQPanelDraft(value: QQConnectionForm(QQConfig()))
    var replyDraft = QQPanelDraft(value: QQReplyForm(QQConfig()))
    var imageDraft = QQPanelDraft(value: QQImageGenerationConfig())
    var visualDraft = QQPanelDraft(value: QQVisualConfig())
    var artworkDraft = QQPanelDraft(value: QQArtworkForm(QQArtworkConfig()))
    var artistInput = ""
    var hasCredentialDrafts: Bool {
        !token.isEmpty || !temporaryKey.isEmpty || !imageZhipuKey.isEmpty || !imageCloudflareToken.isEmpty || !googleVisionKey.isEmpty
    }
    mutating func refresh(_ config: QQConfig) {
        connectionDraft.refresh(QQConnectionForm(config)); replyDraft.refresh(QQReplyForm(config))
        imageDraft.refresh(config.effectiveImageGeneration); visualDraft.refresh(config.effectiveVisualTools)
        artworkDraft.refresh(QQArtworkForm(config.effectiveArtwork))
    }
}

struct QQArtworkForm: Equatable {
    var settings: QQArtworkConfig
    var artists: String
    var networkDailyLimit: String
    var minLongEdge: String
    var minShortEdge: String
    var searchMinBookmarks: String
    init(_ settings: QQArtworkConfig) {
        self.settings = settings; artists = settings.pixivArtistIDs.joined(separator: ",")
        networkDailyLimit = String(settings.networkDailyLimit)
        minLongEdge = String(settings.minLongEdge); minShortEdge = String(settings.minShortEdge)
        searchMinBookmarks = String(settings.effectiveSearchMinBookmarks)
    }
    // Keep the exact editor text until the whole form can be validated. A failed
    // number conversion must not silently save the previous integer binding.
    func validatedSettings() throws -> QQArtworkConfig {
        func integer(_ raw: String, label: String) throws -> Int {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(value) else {
                throw AppFailure.message("\(label)必须填写非负整数，不能留空")
            }
            return number
        }
        var updated = settings
        updated.networkDailyLimit = try integer(networkDailyLimit, label: "每日来源请求数")
        updated.minLongEdge = try integer(minLongEdge, label: "最小长边像素")
        updated.minShortEdge = try integer(minShortEdge, label: "最小短边像素")
        updated.effectiveSearchMinBookmarks = try integer(searchMinBookmarks, label: "/search 最低收藏数")
        updated.pixivArtistIDs = artists.components(separatedBy: CharacterSet(charactersIn: ",， \n")).filter { !$0.isEmpty }
        updated.artistNames = updated.artistNames?.filter { updated.pixivArtistIDs.contains($0.key) }
        updated.imagePermissions = updated.imagePermissions.filter { updated.pixivArtistIDs.contains($0.key) }
        try updated.validate()
        return updated
    }
}
