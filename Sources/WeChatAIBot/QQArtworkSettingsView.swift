import SwiftUI
import BotCore

struct QQArtworkSettingsView: View {
    @ObservedObject var engine: QQEngine
    @Binding var draft: QQPanelDraft<QQArtworkForm>
    @Binding var artistInput: String
    var body: some View {
        GroupBox("精选插画 · Pixiv 日榜") {
            VStack(alignment: .leading, spacing: 10) {
                if draft.hasChanges {
                    Text(draft.conflicts(with: QQArtworkForm(engine.config.effectiveArtwork)) ? "插画设置已在别处更新，草稿保留" : "插画设置有未保存草稿").foregroundStyle(.orange)
                    Button("放弃插画草稿，载入最新设置") { draft.reset(QQArtworkForm(engine.config.effectiveArtwork)); artistInput = "" }
                }
                Text("/search 白发 猫耳 · /search 作品ID · /hot · /next").font(.headline)
                Text("/search 统一关键词与作品 ID / 链接查询，/art 是兼容别名。关键词优先收藏达标作品；本轮没有达标图时按真实收藏、点赞和浏览量挑选保底，并标明降级。ID 直查不要求收藏门槛。/hot 按日榜排名取图；/next 继续当前条件，ID 直查后须带新关键词。")
                Text("命令不调用模型，仅在已启用会话生效，群内无需 @。只发公开可取得的图片，附作者与出处；不单发作品链接。Hot 不应用美少女主题、宣传标题或最低尺寸门槛，其余模式仍遵守下方画质设置。")
                Toggle("启用插画命令", isOn: $draft.value.settings.enabled)
                Toggle("允许 Agent 通过自然语言调用（会使用模型）", isOn: $draft.value.settings.agentEnabled)
                HStack {
                    Stepper("单会话每天 \(draft.value.settings.dailyPerChat) 张", value: $draft.value.settings.dailyPerChat, in: 1...1000)
                    Stepper("去重 \(draft.value.settings.repeatDays) 天", value: $draft.value.settings.repeatDays, in: 1...90)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("每日来源请求数（10–2000）").font(.caption).foregroundStyle(.secondary)
                        TextField("每日来源请求数", text: $draft.value.networkDailyLimit)
                    }
                    VStack(alignment: .leading) {
                        Text("最小长边像素（0–4096）").font(.caption).foregroundStyle(.secondary)
                        TextField("最小长边像素", text: $draft.value.minLongEdge)
                    }
                    VStack(alignment: .leading) {
                        Text("最小短边像素（0–4096）").font(.caption).foregroundStyle(.secondary)
                        TextField("最小短边像素", text: $draft.value.minShortEdge)
                    }
                }
                Text("/search 优先收藏数（1–1000000）").font(.caption).foregroundStyle(.secondary)
                TextField("/search 优先收藏数（默认1000）", text: $draft.value.searchMinBookmarks)
                Text("数字框须填写整数；无尺寸门槛请填 0。无效输入会保留，修正后再保存。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("高级：历史精选来源") {
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Pixiv 画师主页链接或数字 ID", text: $artistInput)
                            Button("核对名称并添加") {
                                Task { await engine.addArtworkArtist(artistInput); if engine.error == nil { artistInput = "" } }
                            }.disabled(artistInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.hasChanges)
                        }
                        Text("仅用于历史美少女精选定时来源，不限制 /search、ID 直查或 /hot。先暂停再修改；有草稿时请先保存或放弃，再增删画师。添加后立即保存，不调用模型，按公开图片可用性筛选。最多 20 位。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(engine.config.effectiveArtwork.pixivArtistIDs, id: \.self) { id in
                            HStack {
                                Link(QQArtworkLibrary.artistName(id, config: engine.config.effectiveArtwork), destination: URL(string: "https://www.pixiv.net/users/\(id)")!)
                                Text("画师 ID：\(id)").textSelection(.enabled)
                                Text("公开取图，逐作检查可用性").font(.caption).foregroundStyle(.secondary)
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
                HStack {
                    if draft.value.settings.effectiveScheduleFrequency == "daily" { Stepper("\(draft.value.settings.scheduleHour) 时", value: $draft.value.settings.scheduleHour, in: 0...23) }
                    Stepper("\(draft.value.settings.scheduleMinute) 分", value: $draft.value.settings.scheduleMinute, in: 0...59)
                    TextField("时区", text: $draft.value.settings.scheduleTimeZone)
                    Picker("内容", selection: $draft.value.settings.scheduleMode) {
                        Text("Pixiv 日榜").tag("hot"); Text("动漫游戏美少女精选").tag("featured")
                    }
                }
                ForEach(engine.config.targets) { target in
                    Toggle(target.name + (target.enabled ? "" : "（未启用）"), isOn: Binding(get: { draft.value.settings.scheduleTargets.contains(target.key) }, set: { value in
                        draft.value.settings.scheduleTargets.removeAll { $0 == target.key }; if value { draft.value.settings.scheduleTargets.append(target.key) }
                    }))
                }
                Text("每次一张，附取图指令；每小时模式按所选分钟触发。无合格可附图作品则跳过，可从已配置画师的公开作品补选。运行、时段、额度、暂停与原截止仍有效；错过不补发。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("保存插画设置（不启动）") {
                    guard !draft.conflicts(with: QQArtworkForm(engine.config.effectiveArtwork)) else {
                        engine.error = "插画配置已在别处更新，请先载入最新设置"; return
                    }
                    do {
                        engine.saveArtwork(try draft.value.validatedSettings())
                        if engine.error == nil { draft.reset(QQArtworkForm(engine.config.effectiveArtwork)) }
                    } catch { engine.error = error.localizedDescription }
                }
                Text(engine.artworkStatus).font(.caption)
                QQPanelOperationError(message: engine.error)
            }.disabled(engine.running || engine.busy || engine.runtimeBusy)
        }
    }
}
