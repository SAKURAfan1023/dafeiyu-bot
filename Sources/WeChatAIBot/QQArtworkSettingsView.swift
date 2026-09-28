import SwiftUI
import BotCore
private typealias ArtworkViewState<Value> = SwiftUI.State<Value>

struct QQArtworkSettingsView: View {
    @ObservedObject var engine: QQEngine
    @ArtworkViewState private var settings = QQArtworkConfig()
    @ArtworkViewState private var artists = ""
    @ArtworkViewState private var permissions = ""
    @ArtworkViewState private var artistInput = ""
    var body: some View {
        GroupBox("精选插画 · Pixiv 日榜") {
            VStack(alignment: .leading, spacing: 10) {
                Text("/art 原神 · /search 白发 猫耳 · /hot · /artist Anmi 初音未来 · /next").font(.headline)
                Text("/search 关键词全站搜索，优先公开热门候选并核验真实收藏门槛；收藏仅为质量参考，非完整人气排名。/art 带关键词直接查询 Pixiv 搜索结果；/art 不带参数看美少女精选。/hot 从第 1 名按序取图，不限画师与题材；已发过或不可用则顺延。画师带关键词使用来源标签列表，额外条件在列表内匹配。/next 可保留条件或带新关键词替换。")
                Text("命令不调用模型，仅在已启用会话生效，群内无需 @。只发公开可取得的图片，附作者与出处；不单发作品链接。Hot 不应用美少女主题、宣传标题或最低尺寸门槛，其余模式仍遵守下方画质设置。")
                Toggle("启用插画命令", isOn: $settings.enabled)
                Toggle("允许 Agent 通过自然语言调用（会使用模型）", isOn: $settings.agentEnabled)
                HStack {
                    Stepper("单会话每天 \(settings.dailyPerChat) 张", value: $settings.dailyPerChat, in: 1...1000)
                    Stepper("去重 \(settings.repeatDays) 天", value: $settings.repeatDays, in: 1...90)
                }
                HStack {
                    TextField("每日来源请求数", value: $settings.networkDailyLimit, format: .number)
                    TextField("最小长边像素", value: $settings.minLongEdge, format: .number)
                    TextField("最小短边像素", value: $settings.minShortEdge, format: .number)
                }
                TextField("/search 最低收藏数（默认1000）", value: $settings.effectiveSearchMinBookmarks, format: .number)
                DisclosureGroup("画师与历史资料") {
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Pixiv 画师主页链接或数字 ID", text: $artistInput)
                            Button("核对名称并添加") {
                                Task { await engine.addArtworkArtist(artistInput); if engine.error == nil { artistInput = "" } }
                            }.disabled(artistInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("先暂停再修改；添加后立即保存，不调用模型，按公开图片可用性筛选。最多 20 位。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(engine.config.effectiveArtwork.pixivArtistIDs, id: \.self) { id in
                            HStack {
                                Link(QQArtworkLibrary.artistName(id, config: engine.config.effectiveArtwork), destination: URL(string: "https://www.pixiv.net/users/\(id)")!)
                                Text("/artist \(id)").textSelection(.enabled)
                                Text("公开取图，逐作检查可用性").font(.caption).foregroundStyle(.secondary)
                                Button("移除") {
                                    var updated = engine.config.effectiveArtwork
                                    updated.pixivArtistIDs.removeAll { $0 == id }; updated.artistNames?.removeValue(forKey: id)
                                    updated.imagePermissions.removeValue(forKey: id); engine.saveArtwork(updated)
                                }
                            }
                        }
                        TextField("高级：批量画师 ID，逗号分隔", text: $artists)
                        Text("历史许可证据仅保留记录，不再作为取图条件。")
                        TextEditor(text: $permissions).frame(height: 70).disabled(true)
                    }
                }
                Toggle("定时发送（每次一张）", isOn: $settings.scheduleEnabled)
                Picker("频率", selection: Binding(get: { settings.effectiveScheduleFrequency }, set: { settings.scheduleFrequency = $0 })) {
                    Text("每天").tag("daily"); Text("每小时").tag("hourly")
                }
                HStack {
                    if settings.effectiveScheduleFrequency == "daily" { Stepper("\(settings.scheduleHour) 时", value: $settings.scheduleHour, in: 0...23) }
                    Stepper("\(settings.scheduleMinute) 分", value: $settings.scheduleMinute, in: 0...59)
                    TextField("时区", text: $settings.scheduleTimeZone)
                    Picker("内容", selection: $settings.scheduleMode) {
                        Text("Pixiv 日榜").tag("hot"); Text("动漫游戏美少女精选").tag("featured")
                    }
                }
                ForEach(engine.config.targets) { target in
                    Toggle(target.name + (target.enabled ? "" : "（未启用）"), isOn: Binding(get: { settings.scheduleTargets.contains(target.key) }, set: { value in
                        settings.scheduleTargets.removeAll { $0 == target.key }; if value { settings.scheduleTargets.append(target.key) }
                    }))
                }
                Text("每次一张，附取图指令；每小时模式按所选分钟触发。无合格可附图作品则跳过，可从已配置画师的公开作品补选。运行、时段、额度、暂停与原截止仍有效；错过不补发。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("保存插画设置（不启动）") {
                    settings.pixivArtistIDs = artists.components(separatedBy: CharacterSet(charactersIn: ",， \n")).filter { !$0.isEmpty }
                    settings.artistNames = settings.artistNames?.filter { settings.pixivArtistIDs.contains($0.key) }
                    var parsed: [String: String] = [:]
                    for line in permissions.split(separator: "\n") {
                        let fields = line.split(whereSeparator: { $0.isWhitespace })
                        guard fields.count == 2 else { engine.error = "许可格式应为：画师 ID 空格 HTTPS 链接"; return }
                        parsed[String(fields[0])] = String(fields[1])
                    }
                    settings.imagePermissions = parsed; engine.saveArtwork(settings)
                }
                Text(engine.artworkStatus).font(.caption)
            }.disabled(engine.running || engine.busy || engine.runtimeBusy)
        }.onAppear {
            settings = engine.config.effectiveArtwork
            artists = settings.pixivArtistIDs.joined(separator: ",")
            permissions = settings.imagePermissions.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "\n")
        }.onChange(of: engine.config.effectiveArtwork) { _, updated in
            settings.pixivArtistIDs = updated.pixivArtistIDs; settings.artistNames = updated.artistNames
            settings.imagePermissions = updated.imagePermissions
            artists = updated.pixivArtistIDs.joined(separator: ",")
            permissions = updated.imagePermissions.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "\n")
        }
    }
}
