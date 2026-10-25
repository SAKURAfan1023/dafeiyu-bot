import SwiftUI
import BotCore

private typealias QQViewState<Value> = SwiftUI.State<Value>

struct QQView: View {
    @ObservedObject var engine: QQEngine
    @ObservedObject var wechat: BotEngine
    @Binding var editor: QQPanelState
    @QQViewState private var showingCustomPersona = false
    @QQViewState private var showingStickerLibrary = false
    @QQViewState private var customPersonaBaseline: QQReplyForm?
    private func openCustomPersona() {
        customPersonaBaseline = editor.replyDraft.baseline
        showingCustomPersona = true
    }
    private func saveReplyDraft() {
        guard !editor.replyDraft.conflicts(with: QQReplyForm(engine.config)) else { engine.error = "范围或回复配置已在别处更新，请先载入最新设置"; return }
        let value = editor.replyDraft.value
        do {
            engine.saveReplySettings(ai: try value.validatedAI(), persona: value.persona, onlineEnabled: value.onlineEnabled,
                visionEnabled: value.visionEnabled, memoryEnabled: value.memoryEnabled,
                groupParticipationEnabled: value.groupParticipationEnabled, groupParticipationEvery: value.groupParticipationEvery,
                memoryOptions: value.memoryOptions, enabledTargets: Set(value.targets.filter(\.enabled).map(\.key)))
            if engine.error == nil { editor.replyDraft.reset(QQReplyForm(engine.config)) }
        } catch { engine.error = error.localizedDescription }
    }
    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Circle().fill(engine.connected ? Color.green : PanelTheme.muted.opacity(0.5)).frame(width: 7, height: 7)
                Text(engine.status).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(engine.running ? "自动回复中" : "已暂停")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(PanelTheme.muted)
                if let deadline = engine.runDeadline {
                    Text("至 \(deadline.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(PanelTheme.muted)
                        .help("自动暂停：\(deadline.formatted(date: .abbreviated, time: .standard))")
                }
            }
            HStack(spacing: 0) {
                metric("今日模型调用", value: engine.usage.calls)
                Divider().frame(height: 38).padding(.horizontal, 24)
                metric("已确认发送", value: engine.sends.confirmed)
                Divider().frame(height: 38).padding(.horizontal, 24)
                metric("结果未知", value: engine.sends.uncertain)
                Divider().frame(height: 38).padding(.horizontal, 24)
                metric("待处理消息", value: engine.queuedCount)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(PanelTheme.line, lineWidth: 1))
    }
    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value, format: .number).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(PanelTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var connectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                if editor.connectionDraft.hasChanges || !editor.token.isEmpty || !editor.temporaryKey.isEmpty {
                    if editor.connectionDraft.conflicts(with: QQConnectionForm(engine.config)) {
                        Text("连接配置已在别处更新，请先载入最新设置").foregroundStyle(.orange)
                    }
                    Button("放弃连接草稿") { editor.connectionDraft.reset(QQConnectionForm(engine.config)); editor.token = ""; editor.temporaryKey = "" }
                }
                LabeledContent("OneBot 地址") {
                    TextField("ws://127.0.0.1:3001", text: $editor.connectionDraft.value.endpoint)
                }.labeledContentStyle(PanelLabeledContentStyle()).disabled(engine.connected || engine.busy || engine.runtimeBusy)
                LabeledContent("机器人 QQ 号") {
                    TextField("预期登录 QQ 号", text: $editor.connectionDraft.value.expectedSelfID)
                }.labeledContentStyle(PanelLabeledContentStyle()).disabled(engine.connected || engine.busy || engine.runtimeBusy)
                LabeledContent("OneBot 令牌") {
                    SecureField("留空保留已保存值", text: $editor.token)
                }.labeledContentStyle(PanelLabeledContentStyle()).disabled(engine.connected || engine.busy || engine.runtimeBusy)
                HStack(spacing: 10) {
                    Button("保存连接设置") {
                        guard !editor.connectionDraft.conflicts(with: QQConnectionForm(engine.config)) else { engine.error = "连接配置已更新，请先载入最新设置"; return }
                        let saved = engine.save(token: editor.token, endpoint: editor.connectionDraft.value.endpoint, expectedSelfID: editor.connectionDraft.value.expectedSelfID)
                        if saved { editor.connectionDraft.reset(QQConnectionForm(engine.config)) }
                        if engine.error == nil { editor.token = "" }
                    }
                    Button("连接并核对账号") { Task { await engine.connect() } }
                        .buttonStyle(PanelButtonStyle(kind: .primary))
                        .disabled(editor.connectionDraft.hasChanges || !editor.token.isEmpty)
                    if engine.busy || engine.runtimeBusy { ProgressView().controlSize(.small) }
                }.disabled(engine.connected || engine.busy || engine.runtimeBusy)
                DisclosureGroup("临时凭证") {
                    VStack(alignment: .leading, spacing: 14) {
                        SecureField("仅本次运行的 DeepSeek Key", text: $editor.temporaryKey)
                            .disabled(engine.connected || engine.busy || engine.runtimeBusy)
                        Button("使用临时凭证连接") {
                            guard !editor.connectionDraft.conflicts(with: QQConnectionForm(engine.config)) else { engine.error = "连接配置已更新，请先载入最新设置"; return }
                            engine.save(endpoint: editor.connectionDraft.value.endpoint, expectedSelfID: editor.connectionDraft.value.expectedSelfID)
                            guard engine.error == nil else { return }
                            editor.connectionDraft.reset(QQConnectionForm(engine.config))
                            guard engine.useTemporaryCredentials(token: editor.token, key: editor.temporaryKey) else { return }
                            editor.token = ""; editor.temporaryKey = ""
                            Task { await engine.connect() }
                        }.disabled(engine.connected || engine.busy || engine.runtimeBusy)
                    }.padding(.top, 12)
                }.font(.system(size: 12)).foregroundStyle(PanelTheme.muted)
                if engine.usesTemporaryCredentials {
                    HStack {
                        Label("使用临时凭证", systemImage: "clock").font(.caption)
                        Button("清除并断开") { engine.clearTemporaryCredentials() }
                    }
                }
            }
        } label: {
            HStack { Text("连接账号"); HelpHint("通过 NapCat / OneBot 11 接入。保存后连接并核对账号；凭证保存到钥匙串，临时凭证只在本次运行有效。") }
        }
    }
    private var runCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Image(systemName: engine.running ? "waveform" : "pause.circle").foregroundStyle(PanelTheme.accent)
                    Text(engine.running ? "回复运行中" : "等待开始").font(.system(size: 14, weight: .medium))
                }
                Text("已启用 \(engine.config.targets.filter(\.enabled).count) 个会话").font(.system(size: 12)).foregroundStyle(PanelTheme.muted)
                LabeledContent("运行时长") {
                    Picker("运行时长", selection: $editor.durationMinutes) {
                        Text("15 分钟").tag(15); Text("30 分钟").tag(30); Text("2 小时").tag(120)
                        Text("3 天（72 小时）").tag(4320); Text("持续运行").tag(0)
                    }.labelsHidden().frame(maxWidth: .infinity)
                }.labeledContentStyle(PanelLabeledContentStyle()).disabled(engine.running || engine.busy || engine.runtimeBusy)
                VStack(spacing: 10) {
                    Button { engine.start(duration: editor.durationMinutes == 0 ? nil : Double(editor.durationMinutes * 60)) } label: {
                        Label("开始回复", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(PanelButtonStyle(kind: .primary))
                        .disabled(!engine.connected || engine.running || engine.busy || engine.runtimeBusy)
                    Button { engine.start(singleReply: true, duration: 15 * 60) } label: { Text("试运行一次").frame(maxWidth: .infinity) }
                        .help("最多回复 1 条，15 分钟后自动暂停")
                        .disabled(!engine.connected || engine.running || engine.busy || engine.runtimeBusy)
                    Button { engine.pause() } label: { Text("暂停 QQ").frame(maxWidth: .infinity) }
                        .buttonStyle(PanelButtonStyle(kind: .quiet))
                }
                Button("断开 QQ") { engine.disconnect() }
                    .buttonStyle(PanelButtonStyle(kind: .quiet))
                    .disabled(!engine.connected && !engine.busy && !engine.runtimeBusy)
            }
        } label: { HStack { Text("运行"); Spacer(); HelpHint("连接账号、勾选会话并保存后开始。单次验收最多回复 1 条；运行时长只在下一次开始时生效。") } }
    }
    private var runtimeCard: some View {
        GroupBox {
            DisclosureGroup("登录与环境管理") {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Button("启动 QQ 环境") { Task { await engine.setRuntime(start: true) } }.disabled(engine.connected || engine.busy || engine.runtimeBusy)
                        Button("停止 QQ 环境") { Task { await engine.setRuntime(start: false) } }.disabled(engine.busy || engine.runtimeBusy)
                        Link("QQ 登录页 ↗", destination: URL(string: "http://127.0.0.1:6099/webui")!)
                        Button("打开原版 QQ") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/QQ.app")) }
                    }
                    HStack(spacing: 12) {
                        SecureField("NapCat 管理令牌（已保存可留空）", text: $editor.webToken)
                        Button("获取／刷新登录码") {
                            Task { await engine.refreshLoginCode(token: editor.webToken); if engine.error == nil { editor.webToken = "" } }
                        }
                    }.disabled(engine.connected || engine.busy || engine.runtimeBusy)
                    if let code = engine.loginCode {
                        Image(nsImage: code).interpolation(.none).resizable().frame(width: 240, height: 240)
                    }
                    Link("社区接入说明 ↗", destination: URL(string: "https://github.com/NapNeko/NapCat-Docker")!).font(.caption)
                }.padding(.top, 18)
            }.font(.system(size: 13)).foregroundStyle(PanelTheme.muted)
        } label: { Text("QQ 环境") }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            statusSummary
            if let error = engine.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if editor.section != "连接与运行" {
                HStack {
                    Spacer()
                    Button("使用推荐配置") { editor.useRecommendedSettings() }
                        .help("填入当前页推荐参数；保留账号、密钥与会话名单，保存后生效")
                        .disabled(engine.running || engine.busy || engine.runtimeBusy)
                }
            }
            if editor.replyDraft.hasChanges || editor.imageDraft.hasChanges || editor.visualDraft.hasChanges || editor.connectionDraft.hasChanges || editor.artworkDraft.hasChanges || editor.hasCredentialDrafts {
                Text("有未保存修改").foregroundStyle(.orange)
            }
            if !engine.configurationHints.isEmpty {
                GroupBox("已保存配置的生效检查") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(engine.configurationHints, id: \.self) { hint in
                            Label(hint, systemImage: "info.circle").font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            if editor.section == "连接与运行" {
                HStack(alignment: .top, spacing: 20) {
                    connectionCard.frame(maxWidth: .infinity)
                    runCard.frame(width: 270)
                }
                runtimeCard
            }
            if editor.section == "范围与回复" {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if editor.replyDraft.hasChanges {
                        if editor.replyDraft.conflicts(with: QQReplyForm(engine.config)) { Text("范围与回复已在别处更新，请先载入最新设置").foregroundStyle(.orange) }
                        Button("放弃范围与回复草稿，载入最新设置") { editor.replyDraft.reset(QQReplyForm(engine.config)) }
                    }
                    ForEach($editor.replyDraft.value.targets) { $target in
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $target.enabled) { Text("\(target.group ? "群" : "好友") · \(target.name) (\(target.number))") }.disabled(engine.running || engine.busy || engine.runtimeBusy)
                            HStack {
                                Picker("性格", selection: Binding(get: { target.personaStyle?.rawValue ?? "default" }, set: { engine.setPersonaStyle($0, target: target.key) })) {
                                    Text("跟随默认").tag("default")
                                    ForEach(QQPersonality.allCases, id: \.rawValue) { style in Text(style.name).tag(style.rawValue) }
                                }.frame(width: 150).disabled(engine.running || engine.busy || engine.runtimeBusy || editor.replyDraft.hasChanges)
                                Button("接管") { engine.takeOver(target.id) }
                                Button("清除记忆并暂停") { engine.clearMemory(target.id) }
                                Button("移除") { engine.remove(target.id) }.disabled(engine.running || engine.busy || engine.runtimeBusy || editor.replyDraft.hasChanges)
                            }
                        }
                    }
                    if engine.config.targets.isEmpty { Text("暂无会话，请连接后添加") }
                    TextField("筛选联系人或群号", text: $editor.search)
                    ForEach(engine.contacts.filter { editor.search.isEmpty || $0.name.localizedCaseInsensitiveContains(editor.search) || $0.number.contains(editor.search) }.prefix(30)) { contact in
                        HStack {
                            Text("\(contact.group ? "群" : "好友") · \(contact.name) (\(contact.number))")
                            Spacer()
                            Button("添加到名单") { engine.add(contact) }.disabled(engine.running || engine.busy || engine.runtimeBusy || editor.replyDraft.hasChanges || engine.config.targets.contains { $0.key == contact.id })
                        }.font(.callout)
                    }
                    Button("保存范围与回复") { saveReplyDraft() }
                        .disabled(engine.running || engine.busy || engine.runtimeBusy)
                }.padding(8)
            } label: { HStack { Text("回复范围 · 最多 20 个会话"); HelpHint("只回复启用的会话。增删和性格切换立即保存，启用勾选需单独保存。群聊响应真实 @，主动接话须另行开启。人工接管会暂停队列并禁用该会话。") } }
            }
            if editor.section == "图片与工具" {
            Picker("图片工具", selection: $editor.toolSection) {
                Text("插画与定时").tag("插画与定时")
                Text("AI 生图").tag("AI 生图")
                Text("识图与搜图").tag("识图与搜图")
            }.pickerStyle(.segmented)
            if editor.toolSection == "插画与定时" {
            QQArtworkSettingsView(engine: engine, draft: $editor.artworkDraft, artistInput: $editor.artistInput)
            }
            if editor.toolSection == "AI 生图" {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if editor.imageDraft.hasChanges || !editor.imageZhipuKey.isEmpty || !editor.imageCloudflareToken.isEmpty {
                        if editor.imageDraft.conflicts(with: engine.config.effectiveImageGeneration) { Text("生图配置已在别处更新，请先载入最新设置").foregroundStyle(.orange) }
                        Button("放弃生图草稿，载入最新设置") { editor.imageDraft.reset(engine.config.effectiveImageGeneration); editor.imageZhipuKey = ""; editor.imageCloudflareToken = "" }
                    }
                    Toggle("启用 AI 生图", isOn: $editor.imageDraft.value.enabled)
                    Picker("默认模型", selection: $editor.imageDraft.value.primary) {
                        ForEach(QQImageProvider.allCases, id: \.self) { provider in Text(provider.title).tag(provider) }
                    }
                    Toggle("默认失败后尝试另一个模型一次", isOn: $editor.imageDraft.value.fallbackEnabled)
                    Text("智谱 API Key（留空保留）").font(.caption).foregroundStyle(.secondary)
                    SecureField("智谱 API Key（留空保留）", text: $editor.imageZhipuKey)
                    Text("Cloudflare Account ID").font(.caption).foregroundStyle(.secondary)
                    TextField("Cloudflare Account ID", text: $editor.imageDraft.value.cloudflareAccountID)
                    SecureField("Cloudflare API Token（Workers AI 权限，留空保留）", text: $editor.imageCloudflareToken)
                    Toggle("保存密钥到钥匙串", isOn: $editor.persistImageCredentials)
                    Text("智谱 \(engine.hasZhipuImageKey ? "已载入" : "未载入") · Cloudflare \(engine.hasCloudflareImageToken ? "已载入" : "未载入")").font(.caption)
                    Button("保存生图设置") {
                        guard !editor.imageDraft.conflicts(with: engine.config.effectiveImageGeneration) else { engine.error = "生图配置已更新，请先载入最新设置"; return }
                        let saved = engine.saveImageGeneration(editor.imageDraft.value, zhipuKey: editor.imageZhipuKey, cloudflareToken: editor.imageCloudflareToken, persistCredentials: editor.persistImageCredentials)
                        if saved { editor.imageDraft.reset(engine.config.effectiveImageGeneration) }
                        if engine.error == nil { editor.imageZhipuKey = ""; editor.imageCloudflareToken = "" }
                    }
                    if engine.imageGenerationStatus != "尚未调用生图" { Text(engine.imageGenerationStatus).font(.callout) }
                    QQPanelOperationError(message: engine.error)
                }.padding(8).disabled(engine.running || engine.busy || engine.runtimeBusy)
            } label: { HStack { Text("画图 · 双模型自动切换"); HelpHint("明确要求画图时调用，每次一张。默认服务异常时可切换，取消或审核拒绝不切换。调用占每日额度；Cloudflare 付费账户超出免费额度可能计费。") } }
            }
            if editor.toolSection == "识图与搜图" {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if editor.visualDraft.hasChanges || !editor.googleVisionKey.isEmpty {
                        if editor.visualDraft.conflicts(with: engine.config.effectiveVisualTools) { Text("识图配置已在别处更新，请先载入最新设置").foregroundStyle(.orange) }
                        Button("放弃识图草稿，载入最新设置") { editor.visualDraft.reset(engine.config.effectiveVisualTools); editor.googleVisionKey = "" }
                    }
                    Picker("识图服务", selection: $editor.visualDraft.value.provider) {
                        ForEach(QQVisionProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Google 以图搜图", isOn: $editor.visualDraft.value.googleWebEnabled)
                    SecureField("Google Cloud Vision API Key（留空保留）", text: $editor.googleVisionKey)
                    Toggle("保存 Google Key 到钥匙串", isOn: $editor.persistVisualCredentials)
                    Text(engine.hasGoogleVisionKey ? "Google 凭证已载入" : "Google 凭证未载入").font(.caption)
                    Link("开通 Cloud Vision API", destination: URL(string: "https://console.cloud.google.com/apis/library/vision.googleapis.com")!)
                    Button("保存识图设置") {
                        guard !editor.visualDraft.conflicts(with: engine.config.effectiveVisualTools) else { engine.error = "识图配置已更新，请先载入最新设置"; return }
                        let saved = engine.saveVisualTools(editor.visualDraft.value, googleKey: editor.googleVisionKey, persistCredentials: editor.persistVisualCredentials)
                        if saved { editor.visualDraft.reset(engine.config.effectiveVisualTools) }
                        if engine.error == nil { editor.googleVisionKey = "" }
                    }
                    if engine.visualStatus != "尚未调用外置识图或搜图" { Text(engine.visualStatus).font(.callout) }
                    QQPanelOperationError(message: engine.error)
                }.padding(8).disabled(engine.running || engine.busy || engine.runtimeBusy)
            } label: { HStack { Text("识图与 Google 以图搜图"); HelpHint("智谱复用生图 Key。动图最多抽取 6 帧，每轮最多 12 帧，不保存原图。Google 还需启用识图和联网，只返回文字与来源，超免费额度可能计费。") } }
            }
            }
            if editor.section == "范围与回复" {
                GroupBox {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 18) {
                            LabeledContent("默认性格") {
                                Picker("默认性格", selection: Binding(get: { editor.replyDraft.value.persona.effectiveStyle }, set: { style in
                                    if style == .custom { openCustomPersona() }
                                    else { editor.replyDraft.value.persona.effectiveStyle = style }
                                })) {
                                    ForEach(QQPersonality.allCases, id: \.rawValue) { style in Text(style.name).tag(style).help(style.description) }
                                }.labelsHidden()
                            }.labeledContentStyle(PanelLabeledContentStyle())
                            Button("自定义性格…") { openCustomPersona() }
                            PanelNumberField("回复字数上限", value: $editor.replyDraft.value.persona.maxCharacters, in: 20...200, unit: "字")
                            LabeledContent("雌小鬼嘴欠程度") {
                                Picker("雌小鬼嘴欠程度", selection: $editor.replyDraft.value.persona.banter) {
                                    Text("温和").tag(0); Text("轻微吐槽").tag(1); Text("犀利但有分寸").tag(2); Text("锋利回怼").tag(3)
                                }.labelsHidden()
                            }.labeledContentStyle(PanelLabeledContentStyle())
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 18) {
                            Toggle("启用表情配图", isOn: $editor.replyDraft.value.persona.stickersEnabled)
                            LabeledContent("配图方式") {
                                Picker("配图方式", selection: $editor.replyDraft.value.persona.effectiveStickerTrigger) {
                                    Text("按语境与条数").tag(QQStickerTrigger.contextual)
                                    Text("只在指定情绪").tag(QQStickerTrigger.emotions)
                                    Text("收到指定关键词").tag(QQStickerTrigger.keywords)
                                }.labelsHidden()
                            }.labeledContentStyle(PanelLabeledContentStyle())
                            if editor.replyDraft.value.persona.effectiveStickerTrigger == .emotions {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], alignment: .leading, spacing: 10) {
                                    ForEach(QQEmotion.allCases, id: \.self) { emotion in
                                        Toggle(stickerEmotionName(emotion), isOn: Binding(get: { editor.replyDraft.value.persona.effectiveStickerEmotions.contains(emotion) }, set: { enabled in
                                            var emotions = Set(editor.replyDraft.value.persona.effectiveStickerEmotions)
                                            if enabled { emotions.insert(emotion) } else { emotions.remove(emotion) }
                                            editor.replyDraft.value.persona.stickerEmotions = QQEmotion.allCases.filter { emotions.contains($0) }
                                        }))
                                    }
                                }
                            }
                            if editor.replyDraft.value.persona.effectiveStickerTrigger == .keywords {
                                TextField("关键词，用逗号分隔", text: Binding(get: { (editor.replyDraft.value.persona.stickerKeywords ?? []).joined(separator: "，") }, set: { value in
                                    editor.replyDraft.value.persona.stickerKeywords = value.components(separatedBy: CharacterSet(charactersIn: ",，\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                }))
                            }
                            PanelNumberField("配图条数间隔", value: $editor.replyDraft.value.persona.effectiveStickerEveryReplies, in: 0...10, unit: "条")
                                .help("0 为仅在强烈情绪时配图；仍需符合当前语境。")
                            PanelNumberField("两次配图至少间隔", value: $editor.replyDraft.value.persona.stickerIntervalSeconds, in: 1...3600, unit: "秒")
                            PanelNumberField("同图不重复时长", value: $editor.replyDraft.value.persona.effectiveStickerRepeatHours, in: 1...168, unit: "小时")
                            Button("表情库与本机导入（\(engine.stickerLibrary.items.count) 张）") { showingStickerLibrary = true }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } label: { HStack { Text("人设与表情"); HelpHint("性格按会话独立覆盖。配图结合语境，无合适图不硬配；配图间隔为 0 时仅考虑强烈情绪。") } }
                    .disabled(engine.running || engine.busy || engine.runtimeBusy)
                GroupBox {
                    HStack(alignment: .center, spacing: 24) {
                        Toggle("启用主动接话", isOn: $editor.replyDraft.value.groupParticipationEnabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PanelNumberField("主动接话触发条数", value: $editor.replyDraft.value.groupParticipationEvery, in: 1...1000, unit: "条")
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(engine.config.targets.filter { $0.enabled && $0.group }) { target in
                        Text("\(target.name)：\(engine.groupMessageCounts[target.key, default: 0]) / \(editor.replyDraft.value.groupParticipationEvery) 条").font(.caption)
                    }
                } label: { HStack { Text("群聊主动接话"); HelpHint("每群独立计数，包含主人手动发言，@ 不重置计数。达到条数只评估是否接话，可以选择保持安静。") } }
                    .disabled(engine.running || engine.busy || engine.runtimeBusy)
                GroupBox {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 20) {
                            LabeledContent("模型") { TextField("模型", text: $editor.replyDraft.value.ai.model) }.labeledContentStyle(PanelLabeledContentStyle())
                            Button("复制微信 AI 参数") {
                                var ai = wechat.config; ai.chats = []
                                ai.prompt = editor.replyDraft.value.ai.prompt; editor.replyDraft.value.ai = ai
                                editor.replyDraft.value.dailyLimit = String(ai.dailyLimit)
                                editor.replyDraft.value.sendDaily = String(ai.effectiveSendLimits.daily)
                                editor.replyDraft.value.perChatDaily = String(ai.effectiveSendLimits.perChatDaily)
                            }
                        }
                        HStack(spacing: 24) {
                            Toggle("识别图片与表情包", isOn: $editor.replyDraft.value.visionEnabled)
                            Toggle("允许搜索网页和网络图片", isOn: $editor.replyDraft.value.onlineEnabled)
                        }
                        LabeledContent("补充偏好") {
                            TextEditor(text: $editor.replyDraft.value.ai.prompt).frame(height: 100)
                                .modifier(PanelTextEditorStyle()).accessibilityLabel("补充偏好")
                        }.labeledContentStyle(PanelLabeledContentStyle())
                        HStack(alignment: .top, spacing: 20) {
                            PanelNumberField("每日模型调用上限", text: $editor.replyDraft.value.dailyLimit, in: 1...10000, unit: "次")
                            PanelNumberField("每日发送上限", text: $editor.replyDraft.value.sendDaily, in: 1...10000, unit: "条")
                            PanelNumberField("单会话每日发送上限", text: $editor.replyDraft.value.perChatDaily, in: 1...10000, unit: "条")
                        }
                        HStack(spacing: 20) {
                            PanelNumberField("单会话间隔", value: $editor.replyDraft.value.ai.cooldownSeconds, in: 1...300, unit: "秒")
                            PanelNumberField("全局发送间隔", value: $editor.replyDraft.value.ai.effectiveSendLimits.globalIntervalSeconds, in: 1...300, unit: "秒")
                        }
                        Toggle("仅在指定时段回复", isOn: $editor.replyDraft.value.ai.workHoursEnabled)
                        if editor.replyDraft.value.ai.workHoursEnabled {
                            HStack(spacing: 20) {
                                PanelNumberField("开始时间", value: $editor.replyDraft.value.ai.workStart, in: 0...23, unit: "时")
                                PanelNumberField("结束时间", value: $editor.replyDraft.value.ai.workEnd, in: 0...23, unit: "时")
                            }
                        }
                        if engine.rejectedScopedEvents > 0 { Text("规则跳过 \(engine.rejectedScopedEvents) 条").font(.callout) }
                    }
                } label: { HStack { Text("模型与回复"); HelpHint("每条通常包含生成与语义校对两次模型调用。修改额度不重置今日用量；保存不会启动回复。工作时段使用本机时区，可跨午夜，起止相同表示全天。") } }
                    .disabled(engine.running || engine.busy || engine.runtimeBusy)
                Button("保存范围与回复") { saveReplyDraft() }.buttonStyle(PanelButtonStyle(kind: .primary))
                    .disabled(engine.running || engine.busy || engine.runtimeBusy)
                QQPanelOperationError(message: engine.error)
            }
            if editor.section == "记忆与记录" {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("独立会话记忆与自动压缩", isOn: $editor.replyDraft.value.memoryEnabled)
                    HStack(spacing: 20) {
                        PanelNumberField("累计消息数", value: $editor.replyDraft.value.memoryOptions.messageThreshold, in: 4...100, unit: "条")
                        PanelNumberField("累计字符数", value: $editor.replyDraft.value.memoryOptions.characterThreshold, in: 1000...20000, step: 1000, unit: "字")
                    }
                    HStack(spacing: 20) {
                        PanelNumberField("整理时间阈值", value: $editor.replyDraft.value.memoryOptions.intervalMinutes, in: 1...120, unit: "分钟")
                        PanelNumberField("每轮检索预算", value: $editor.replyDraft.value.memoryOptions.retrievalCharacters, in: 600...4000, step: 200, unit: "字")
                    }
                    if engine.memoryStatus != "记忆等待新消息" { Text(engine.memoryStatus).font(.callout) }
                    Button("保存记忆与回复设置") { saveReplyDraft() }
                }.padding(8).disabled(engine.running || engine.busy || engine.runtimeBusy)
            } label: { HStack { Text("记忆设置"); HelpHint("每群、每好友独立保存，群内保留说话人。按消息数、字符数或时间整理，暂停保留待整理片段；后台整理占模型额度。") } }
            DisclosureGroup("已保存的会话记忆") {
                ForEach(engine.memoryBooks.keys.filter { $0.hasPrefix(engine.config.expectedSelfID + ":") }.sorted(), id: \.self) { key in
                    if let book = engine.memoryBooks[key] {
                        Text("\(key)：\(book.items.filter { $0.current(Date()) }.count) 项记忆，\(book.pending.count) 条待整理，容量丢弃 \(book.droppedEvents) 条")
                        ForEach(book.items.filter { $0.current(Date()) }.suffix(32)) { item in Text("[\(item.subject)·\(item.kind)] \(item.text)").textSelection(.enabled) }
                    }
                }
            }
            if !engine.preview.isEmpty { GroupBox("本次回复预览（不落盘）") { Text(engine.preview).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) } }
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if engine.runtimeRecords.isEmpty { Text("暂无运行记录").font(.caption) }
                    ForEach(engine.runtimeRecords) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title).fontWeight(.semibold)
                                    .foregroundStyle(item.state == .failed || item.state == .uncertain ? Color.orange : Color.primary)
                                Text(item.target).foregroundStyle(.secondary)
                            }
                            Text(Date(timeIntervalSince1970: item.timestamp).formatted(date: .abbreviated, time: .standard)).foregroundStyle(.secondary)
                            Text(item.detail).textSelection(.enabled)
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            } label: { HStack { Text("近期运行结果"); HelpHint("最近 30 条，新记录在前。发送确认不代表对方已读，规则跳过不等于故障。记录不包含所有入站消息，也不代表回复质量。") } }
            }
        }.textFieldStyle(PanelTextFieldStyle()).groupBoxStyle(PanelGroupBoxStyle())
            .buttonStyle(PanelButtonStyle()).controlSize(.large)
        .onAppear { editor.refresh(engine.config) }
        .onChange(of: engine.config) { _, current in editor.refresh(current) }
        .sheet(isPresented: $showingCustomPersona) {
            QQCustomPersonaEditor(persona: editor.replyDraft.value.persona) { persona in
                guard !engine.running, !engine.busy, !engine.runtimeBusy else { throw AppFailure.message("请先暂停并等待当前操作完成") }
                guard customPersonaBaseline == QQReplyForm(engine.config) else { throw AppFailure.message("配置已在别处更新；本窗口输入保留，请关闭后重新核对设置") }
                editor.replyDraft.value.persona = persona
            }
        }
        .sheet(isPresented: $showingStickerLibrary) { QQStickerManager(engine: engine) }
    }
}

/// The engine owns one latest error, so repeated local feedback must not imply
/// that unrelated forms each failed or that a partial credential save rolled back.
struct QQPanelOperationError: View {
    let message: String?
    var body: some View {
        if let message {
            Label("最近一次操作提示：\(message)", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
