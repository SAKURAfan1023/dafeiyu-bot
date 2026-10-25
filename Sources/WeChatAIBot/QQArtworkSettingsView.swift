import SwiftUI
import BotCore

struct QQArtworkSettingsView: View {
    @ObservedObject var engine: QQEngine
    @Binding var draft: QQPanelDraft<QQArtworkForm>
    @Binding var artistInput: String
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                if draft.hasChanges {
                    if draft.conflicts(with: QQArtworkForm(engine.config.effectiveArtwork)) { Text("插画设置已在别处更新，请先载入最新设置").foregroundStyle(.orange) }
                    Button("放弃插画草稿，载入最新设置") { draft.reset(QQArtworkForm(engine.config.effectiveArtwork)); artistInput = "" }
                }
                Toggle("启用插画命令", isOn: $draft.value.settings.enabled)
                Toggle("允许 Agent 通过自然语言调用（会使用模型）", isOn: $draft.value.settings.agentEnabled)
                HStack {
                    PanelNumberField("单会话每日作品上限", value: $draft.value.settings.dailyPerChat, in: 1...1000, unit: "张")
                    PanelNumberField("同图不重复时长", value: $draft.value.settings.repeatDays, in: 1...7, unit: "天")
                }
                HStack(alignment: .top, spacing: 20) {
                    PanelNumberField("每日来源请求数", text: $draft.value.networkDailyLimit, in: 10...2000, unit: "次")
                    PanelNumberField("/search 优先收藏数", text: $draft.value.searchMinBookmarks, in: 1...1000000)
                }
                HStack(spacing: 20) {
                    PanelNumberField("最小长边", text: $draft.value.minLongEdge, in: 0...4096, unit: "px")
                    PanelNumberField("最小短边", text: $draft.value.minShortEdge, in: 0...4096, unit: "px")
                }
                DisclosureGroup("高级：历史精选来源") {
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Pixiv 画师主页链接或数字 ID", text: $artistInput)
                            Button("核对名称并添加") {
                                Task { await engine.addArtworkArtist(artistInput); if engine.error == nil { artistInput = "" } }
                            }.disabled(artistInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.hasChanges)
                        }
                        ForEach(engine.config.effectiveArtwork.pixivArtistIDs, id: \.self) { id in
                            HStack {
                                Link(QQArtworkLibrary.artistName(id, config: engine.config.effectiveArtwork), destination: URL(string: "https://www.pixiv.net/users/\(id)")!)
                                Text("画师 ID：\(id)").textSelection(.enabled)
                                Button("移除") {
                                    var updated = engine.config.effectiveArtwork
                                    updated.pixivArtistIDs.removeAll { $0 == id }; updated.artistNames?.removeValue(forKey: id)
                                    updated.imagePermissions.removeValue(forKey: id); engine.saveArtwork(updated)
                                }.disabled(draft.hasChanges)
                            }
                        }
                        TextField("高级：批量画师 ID，逗号分隔", text: $draft.value.artists)
                        Text("历史许可证据仅保留记录，不再作为取图条件。")
                        Text(draft.value.settings.imagePermissions.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "\n")).textSelection(.enabled)
                    }
                }
                Toggle("定时发送（每次一张）", isOn: $draft.value.settings.scheduleEnabled)
                Picker("频率", selection: Binding(get: { draft.value.settings.effectiveScheduleFrequency }, set: { draft.value.settings.scheduleFrequency = $0 })) {
                    Text("每天").tag("daily"); Text("每小时").tag("hourly")
                }
                HStack(spacing: 20) {
                    PanelNumberField("发送时间", value: $draft.value.settings.scheduleHour, in: 0...23, unit: "时")
                        .disabled(draft.value.settings.effectiveScheduleFrequency == "hourly")
                    PanelNumberField("发送分钟", value: $draft.value.settings.scheduleMinute, in: 0...59, unit: "分")
                }
                HStack(spacing: 20) {
                    LabeledContent("时区") { TextField("时区", text: $draft.value.settings.scheduleTimeZone) }.labeledContentStyle(PanelLabeledContentStyle())
                    LabeledContent("内容") {
                        Picker("内容", selection: $draft.value.settings.scheduleMode) {
                            Text("Pixiv 日榜").tag("hot"); Text("动漫游戏美少女精选").tag("featured")
                        }.labelsHidden()
                    }.labeledContentStyle(PanelLabeledContentStyle())
                }
                ForEach(engine.config.targets) { target in
                    Toggle(target.name + (target.enabled ? "" : "（未启用）"), isOn: Binding(get: { draft.value.settings.scheduleTargets.contains(target.key) }, set: { value in
                        draft.value.settings.scheduleTargets.removeAll { $0 == target.key }; if value { draft.value.settings.scheduleTargets.append(target.key) }
                    }))
                }
                Button("保存插画设置") {
                    guard !draft.conflicts(with: QQArtworkForm(engine.config.effectiveArtwork)) else {
                        engine.error = "插画配置已在别处更新，请先载入最新设置"; return
                    }
                    do {
                        engine.saveArtwork(try draft.value.validatedSettings())
                        if engine.error == nil { draft.reset(QQArtworkForm(engine.config.effectiveArtwork)) }
                    } catch { engine.error = error.localizedDescription }
                }
                if engine.artworkStatus != "插画尚未请求" { Text(engine.artworkStatus).font(.callout) }
                QQPanelOperationError(message: engine.error)
            }.disabled(engine.running || engine.busy || engine.runtimeBusy)
        } label: { HStack { Text("精选插画 · Pixiv 日榜"); HelpHint("/search 关键词、作品 ID 或链接；/hot 按日榜顺序；/next 继续当前条件。命令不调用模型，Agent 会调用模型。搜索优先收藏达标图，无达标候选时按真实热度保底。定时仅在运行且目标启用时生效，错过不补发。") } }
    }
}
