import SwiftUI
import BotCore

struct QQView: View {
    @ObservedObject var engine: QQEngine
    @ObservedObject var wechat: BotEngine
    @Binding var editor: QQPanelState
    private func saveReplyDraft() {
        guard !editor.replyDraft.conflicts(with: QQReplyForm(engine.config)) else { engine.error = "范围或回复配置已在别处更新，请先载入最新设置"; return }
        let value = editor.replyDraft.value
        engine.saveReplySettings(ai: value.ai, persona: value.persona, onlineEnabled: value.onlineEnabled,
            visionEnabled: value.visionEnabled, memoryEnabled: value.memoryEnabled,
            groupParticipationEnabled: value.groupParticipationEnabled, groupParticipationEvery: value.groupParticipationEvery,
            memoryOptions: value.memoryOptions, enabledTargets: Set(value.targets.filter(\.enabled).map(\.key)))
        if engine.error == nil { editor.replyDraft.reset(QQReplyForm(engine.config)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("大肥鱼 · QQ 控制台", systemImage: "bubble.left.and.bubble.right.fill").font(.title2.bold())
                        Text(engine.status).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("暂停全部 QQ 回复") { engine.pause() }.tint(.red)
                }
                HStack(spacing: 20) {
                    Label(engine.connected ? "账号已核对" : "等待连接", systemImage: engine.connected ? "checkmark.circle.fill" : "circle")
                    Text("已选范围 \(engine.config.targets.filter(\.enabled).count) 个会话")
                    Text(engine.running ? "正在自动回复" : "尚未开始 / 已暂停")
                }.font(.callout)
                HStack(spacing: 20) {
                    Text("今日调用 \(engine.usage.calls)")
                    Text("发送确认 \(engine.sends.confirmed)")
                    Text("结果未知 \(engine.sends.uncertain)")
                    Text("队列 \(engine.queuedCount) / \(QQEngine.queueCapacity)")
                }.font(.caption).foregroundStyle(.secondary)
                if let deadline = engine.runDeadline {
                    Text("自动暂停：\(deadline.formatted(date: .abbreviated, time: .standard))").font(.callout)
                } else if engine.running {
                    Text("当前持续运行，需手动暂停").font(.callout)
                }
                Text("连接账号 → 选择回复范围 → 保存设置 → 开始回复。保存配置不会自动发送消息。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            if let error = engine.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            Picker("QQ 面板分区", selection: $editor.section) {
                Text("连接与运行").tag("连接与运行")
                Text("范围与回复").tag("范围与回复")
                Text("图片与工具").tag("图片与工具")
                Text("记忆与记录").tag("记忆与记录")
            }.pickerStyle(.segmented)
            if editor.replyDraft.hasChanges || editor.imageDraft.hasChanges || editor.visualDraft.hasChanges || editor.connectionDraft.hasChanges || editor.artworkDraft.hasChanges || editor.hasCredentialDrafts {
                Text("有未保存草稿。各区域保存后才会生效；开始回复使用已保存配置。").foregroundStyle(.orange)
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
            GroupBox("QQ 连接 · NapCat / OneBot 11") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(engine.status).font(.headline)
                    if editor.connectionDraft.hasChanges || !editor.token.isEmpty || !editor.temporaryKey.isEmpty {
                        Text(editor.connectionDraft.conflicts(with: QQConnectionForm(engine.config)) ? "连接配置冲突，草稿尚未提交" : "连接配置有未保存修改").foregroundStyle(.orange)
                        Button("放弃连接草稿，载入最新设置") { editor.connectionDraft.reset(QQConnectionForm(engine.config)); editor.token = ""; editor.temporaryKey = "" }
                    }
                    Text("QQ 与 NapCat 在本机独立 Linux 环境运行，通过登录页扫码。微信与 QQ 独立启停。群聊响应真实 @，也可开启按消息数量主动接话。")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("OneBot 地址", text: $editor.connectionDraft.value.endpoint).disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                    TextField("预期登录 QQ 号", text: $editor.connectionDraft.value.expectedSelfID).disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                    SecureField("OneBot Access Token（留空保留已保存值）", text: $editor.token).disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                    HStack {
                        Button("保存连接配置与钥匙串令牌") {
                            guard !editor.connectionDraft.conflicts(with: QQConnectionForm(engine.config)) else { engine.error = "连接配置已更新，请先载入最新设置"; return }
                            let saved = engine.save(token: editor.token, endpoint: editor.connectionDraft.value.endpoint, expectedSelfID: editor.connectionDraft.value.expectedSelfID)
                            if saved { editor.connectionDraft.reset(QQConnectionForm(engine.config)) }
                            if engine.error == nil { editor.token = "" }
                        }
                        Button("连接并核对账号") { Task { await engine.connect() } }.disabled(editor.connectionDraft.hasChanges || !editor.token.isEmpty)
                        if (engine.busy || engine.runtimeBusy) { ProgressView().controlSize(.small) }
                    }.disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                    DisclosureGroup("钥匙串不可用时：仅本次运行的凭证") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("在上方填写 OneBot 令牌，并在此填写 DeepSeek Key。此按钮保存地址与账号，两个凭证仅保留在当前进程内；连接后仍需手动开始回复。")
                                .font(.caption).foregroundStyle(.secondary)
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
                        }
                    }
                    if engine.usesTemporaryCredentials {
                        HStack {
                            Label("当前使用临时凭证，未保存到钥匙串", systemImage: "clock")
                            Button("清除临时凭证并断开") { engine.clearTemporaryCredentials() }
                        }.font(.caption)
                    }
                    Picker("下次启动的运行时长", selection: $editor.durationMinutes) {
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("2 小时").tag(120)
                        Text("3 天（72 小时）").tag(4320)
                        Text("持续运行，手动暂停").tag(0)
                    }.disabled(engine.running || engine.busy || engine.runtimeBusy)
                    HStack {
                        Button("按已保存配置开始回复") { engine.start(duration: editor.durationMinutes == 0 ? nil : Double(editor.durationMinutes * 60)) }
                            .disabled(!engine.connected || engine.running || engine.busy || engine.runtimeBusy).buttonStyle(.borderedProminent)
                        Button("单次验收（最多 1 条）") { engine.start(singleReply: true, duration: 15 * 60) }
                            .disabled(!engine.connected || engine.running || engine.busy || engine.runtimeBusy)
                        Button("断开 QQ") { engine.disconnect() }.disabled(!engine.connected && !(engine.busy || engine.runtimeBusy))
                    }
                    HStack {
                        Button("启动 QQ 环境") { Task { await engine.setRuntime(start: true) } }.disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                        Button("停止 QQ 环境") { Task { await engine.setRuntime(start: false) } }.disabled((engine.busy || engine.runtimeBusy))
                        Link("QQ 登录页", destination: URL(string: "http://127.0.0.1:6099/webui")!)
                        Button("打开原版 QQ") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/QQ.app")) }
                        Link("社区接入说明", destination: URL(string: "https://github.com/NapNeko/NapCat-Docker")!)
                    }
                    Text("启动前先退出原版 QQ。接口只向本机开放，默认从钥匙串读取令牌。连接成功不会自动开始回复；断线、离线、休眠或账号不一致会停机。停止环境会先暂停回复。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        SecureField("NapCat 管理令牌（已保存可留空）", text: $editor.webToken)
                        Button("获取／刷新登录码") {
                            Task { await engine.refreshLoginCode(token: editor.webToken); if engine.error == nil { editor.webToken = "" } }
                        }
                    }.disabled(engine.connected || engine.busy || engine.runtimeBusy)
                    if let code = engine.loginCode {
                        Image(nsImage: code).interpolation(.none).resizable().frame(width: 280, height: 280)
                        Text("手机 QQ 扫码确认；二维码过期后请重新获取。登录本身不会开启自动回复。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(8)
            }
            }
            if editor.section == "范围与回复" {
            GroupBox("回复范围 · 最多 20 个会话") {
                VStack(alignment: .leading, spacing: 12) {
                    if editor.replyDraft.hasChanges {
                        Text(editor.replyDraft.conflicts(with: QQReplyForm(engine.config)) ? "范围或回复设置已在别处修改。草稿保留，请先载入最新设置。" : "范围与回复设置有未保存草稿").foregroundStyle(.orange)
                        Button("放弃范围与回复草稿，载入最新设置") { editor.replyDraft.reset(QQReplyForm(engine.config)) }
                    }
                    Text(editor.replyDraft.hasChanges ? "请先保存或放弃草稿，再增删会话或切换会话性格。" : "增删会话与切换会话性格会立即保存；启用勾选需单独保存范围与回复设置。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($editor.replyDraft.value.targets) { $target in
                        HStack {
                            Toggle(isOn: $target.enabled) { Text("\(target.group ? "群" : "好友") · \(target.name) (\(target.number))") }.disabled(engine.running || engine.busy || engine.runtimeBusy)
                            Picker("性格", selection: Binding(get: { target.personaStyle?.rawValue ?? "default" }, set: { engine.setPersonaStyle($0, target: target.key) })) {
                                Text("跟随默认").tag("default")
                                ForEach(QQPersonality.allCases, id: \.rawValue) { style in Text(style.name).tag(style.rawValue) }
                            }.frame(width: 150).disabled(engine.running || engine.busy || engine.runtimeBusy || editor.replyDraft.hasChanges)
                            Button("接管") { engine.takeOver(target.id) }
                            Button("清除记忆并暂停") { engine.clearMemory(target.id) }
                            Button("移除") { engine.remove(target.id) }.disabled(engine.running || engine.busy || engine.runtimeBusy || editor.replyDraft.hasChanges)
                        }
                    }
                    Text(QQPersonaCommand.navigation + "。已启用群内无需 @，成员均可切换本群性格；暂停后可在面板调整。").font(.caption)
                    if engine.config.targets.isEmpty { Text("尚未添加。连接后从核对过的好友／群列表选择。默认全部禁用。") }
                    TextField("筛选联系人或群号", text: $editor.search)
                    ForEach(engine.contacts.filter { editor.search.isEmpty || $0.name.localizedCaseInsensitiveContains(editor.search) || $0.number.contains(editor.search) }.prefix(30)) { contact in
                        HStack {
                            Text("\(contact.group ? "群" : "好友") · \(contact.name) (\(contact.number))")
                            Spacer()
                            Button("添加到名单") { engine.add(contact) }.disabled(engine.running || engine.busy || engine.runtimeBusy || editor.replyDraft.hasChanges || engine.config.targets.contains { $0.key == contact.id })
                        }.font(.callout)
                    }
                    Text("列表最多显示 30 条，可输入 QQ 号／群号精确筛选。接管会暂停当前 QQ 队列并禁用该会话。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("保存范围与回复草稿（不启动）") { saveReplyDraft() }
                        .disabled(engine.running || engine.busy || engine.runtimeBusy)
                }.padding(8)
            }
            }
            if editor.section == "图片与工具" {
            QQArtworkSettingsView(engine: engine, draft: $editor.artworkDraft, artistInput: $editor.artistInput)
            GroupBox("画图 · 双模型自动切换") {
                VStack(alignment: .leading, spacing: 10) {
                    if editor.imageDraft.hasChanges || !editor.imageZhipuKey.isEmpty || !editor.imageCloudflareToken.isEmpty {
                        Text(editor.imageDraft.conflicts(with: engine.config.effectiveImageGeneration) ? "生图配置冲突，草稿尚未提交" : "生图配置有未保存修改").foregroundStyle(.orange)
                        Button("放弃生图草稿，载入最新设置") { editor.imageDraft.reset(engine.config.effectiveImageGeneration); editor.imageZhipuKey = ""; editor.imageCloudflareToken = "" }
                    }
                    Toggle("启用 AI 生图（明确要求画图时调用）", isOn: $editor.imageDraft.value.enabled)
                    Picker("默认模型", selection: $editor.imageDraft.value.primary) {
                        ForEach(QQImageProvider.allCases, id: \.self) { provider in Text(provider.title).tag(provider) }
                    }
                    Toggle("默认失败后尝试另一个模型一次", isOn: $editor.imageDraft.value.fallbackEnabled)
                    SecureField("智谱 API Key（留空保留）", text: $editor.imageZhipuKey)
                    TextField("Cloudflare Account ID", text: $editor.imageDraft.value.cloudflareAccountID)
                    SecureField("Cloudflare API Token（Workers AI 权限，留空保留）", text: $editor.imageCloudflareToken)
                    Toggle("新填密钥保存至本机钥匙串（取消则仅本次运行）", isOn: $editor.persistImageCredentials)
                    Text("智谱 \(engine.hasZhipuImageKey ? "已载入" : "未载入") · Cloudflare \(engine.hasCloudflareImageToken ? "已载入" : "未载入")；开始回复时会尝试读取已有钥匙串凭证。").font(.caption)
                    Button("保存生图配置（不启动回复）") {
                        guard !editor.imageDraft.conflicts(with: engine.config.effectiveImageGeneration) else { engine.error = "生图配置已更新，请先载入最新设置"; return }
                        let saved = engine.saveImageGeneration(editor.imageDraft.value, zhipuKey: editor.imageZhipuKey, cloudflareToken: editor.imageCloudflareToken, persistCredentials: editor.persistImageCredentials)
                        if saved { editor.imageDraft.reset(engine.config.effectiveImageGeneration) }
                        if engine.error == nil { editor.imageZhipuKey = ""; editor.imageCloudflareToken = "" }
                    }
                    Text(engine.imageGenerationStatus).font(.caption)
                    Text("直连两平台官方接口。每次最多生成一张；超时/限流/服务异常可切换，取消或审核拒绝不切换。请求计入每日模型调用限额。智谱固定免费 Flash；Cloudflare 请使用 Free 套餐，付费账户超额可能计费。").font(.caption).foregroundStyle(.secondary)
                }.padding(8).disabled(engine.running || engine.busy || engine.runtimeBusy)
            }
            GroupBox("识图与 Google 以图搜图") {
                VStack(alignment: .leading, spacing: 10) {
                    if editor.visualDraft.hasChanges || !editor.googleVisionKey.isEmpty {
                        Text(editor.visualDraft.conflicts(with: engine.config.effectiveVisualTools) ? "识图配置冲突，草稿尚未提交" : "识图配置有未保存修改").foregroundStyle(.orange)
                        Button("放弃识图草稿，载入最新设置") { editor.visualDraft.reset(engine.config.effectiveVisualTools); editor.googleVisionKey = "" }
                    }
                    Picker("识图服务", selection: $editor.visualDraft.value.provider) {
                        ForEach(QQVisionProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("智谱复用生图区域的智谱 Key；主模型拥挤时最多切换一次免费 4.1V 备用。动图按时间最多取 6 帧，每轮最多 12 帧，再由 DeepSeek 理解对话。不保存原图。识图结果仍可能出错。").font(.caption)
                    Toggle("Google Web Detection（明确请求搜图/出处时）", isOn: $editor.visualDraft.value.googleWebEnabled)
                    SecureField("Google Cloud Vision API Key（留空保留）", text: $editor.googleVisionKey)
                    Toggle("保存 Google Key 到钥匙串", isOn: $editor.persistVisualCredentials)
                    Text(engine.hasGoogleVisionKey ? "Google 凭证已载入" : "Google 凭证未载入").font(.caption)
                    Link("开通 Cloud Vision API", destination: URL(string: "https://console.cloud.google.com/apis/library/vision.googleapis.com")!)
                    Text("还需启用识图与联网开关。仅提交一张缩图（动图代表帧），返回文字与来源链接，不回发搜图图片；调用占现有额度，Google 超免费额度可能计费。").font(.caption)
                    Button("保存识图设置（不启动回复）") {
                        guard !editor.visualDraft.conflicts(with: engine.config.effectiveVisualTools) else { engine.error = "识图配置已更新，请先载入最新设置"; return }
                        let saved = engine.saveVisualTools(editor.visualDraft.value, googleKey: editor.googleVisionKey, persistCredentials: editor.persistVisualCredentials)
                        if saved { editor.visualDraft.reset(engine.config.effectiveVisualTools) }
                        if engine.error == nil { editor.googleVisionKey = "" }
                    }
                    Text(engine.visualStatus).font(.caption)
                }.padding(8).disabled(engine.running || engine.busy || engine.runtimeBusy)
            }
            }
            if editor.section == "范围与回复" {
            GroupBox("QQ AI 与限额") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("使用 AI 配置页保存的 DeepSeek Key；QQ 的提示词、调用与发送额度独立统计。")
                    Text("高思考＋发送前语义校对：每条通常至少 2 次调用，生成可能更慢。私聊包含双方最近 20 条消息，区分 OWNER 主人、BOT 大肥鱼和 PEER 好友；来源不明的旧发言单独标记。").font(.caption)
                    HStack {
                        TextField("模型", text: $editor.replyDraft.value.ai.model)
                        Button("复制微信 AI 参数") {
                            var ai = wechat.config; ai.chats = []
                            ai.prompt = editor.replyDraft.value.ai.prompt; editor.replyDraft.value.ai = ai
                        }
                    }
                    Text("大肥鱼 · 成年鲸鱼娘同人角色。会话独立性格优先于默认；切换保留记忆与身份，下面填写补充偏好。").font(.caption)
                    Picker("默认性格", selection: $editor.replyDraft.value.persona.effectiveStyle) {
                        ForEach(QQPersonality.allCases, id: \.rawValue) { style in Text(style.name + " · " + style.description).tag(style) }
                    }
                    Stepper("回复最多 \(editor.replyDraft.value.persona.maxCharacters) 字符", value: $editor.replyDraft.value.persona.maxCharacters, in: 20...200)
                    Picker("雌小鬼嘴欠程度", selection: $editor.replyDraft.value.persona.banter) {
                        Text("温和").tag(0); Text("轻微吐槽").tag(1); Text("犀利但有分寸").tag(2); Text("锋利回怼").tag(3)
                    }
                    Toggle("定期配图，强烈情绪可提前配图", isOn: $editor.replyDraft.value.persona.stickersEnabled)
                    Stepper("每隔 \(editor.replyDraft.value.persona.effectiveStickerEveryReplies) 条回复配图（0 为仅强烈情绪）", value: $editor.replyDraft.value.persona.effectiveStickerEveryReplies, in: 0...10)
                    Text("达到条数后评估，适合才发；结合近期图片，分清主人与群成员，不抢答成员互聊。").font(.caption).foregroundStyle(.secondary)
                    Toggle("按群消息数量评估主动接话", isOn: $editor.replyDraft.value.groupParticipationEnabled)
                    Stepper("每累计 \(editor.replyDraft.value.groupParticipationEvery) 条群消息评估一次接话", value: $editor.replyDraft.value.groupParticipationEvery, in: 1...1000)
                    Text("每群独立计数，包含本账号人工发言；自动回复、重复及历史消息不计入。真实 @ 独立回复，不计入也不重置普通消息进度；暂停清空计数和群聊片段。").font(.caption)
                    ForEach(engine.config.targets.filter { $0.enabled && $0.group }) { target in
                        Text("\(target.name)：\(engine.groupMessageCounts[target.key, default: 0]) / \(editor.replyDraft.value.groupParticipationEvery) 条").font(.caption)
                    }
                    Toggle("允许搜索网页和网络图片", isOn: $editor.replyDraft.value.onlineEnabled)
                    Toggle("识别图片和表情包（使用「图片与工具」中配置的服务，不存原图）", isOn: $editor.replyDraft.value.visionEnabled)
                    Toggle("独立会话记忆与自动压缩", isOn: $editor.replyDraft.value.memoryEnabled)
                    Stepper("记忆每 \(editor.replyDraft.value.memoryOptions.messageThreshold) 条整理", value: $editor.replyDraft.value.memoryOptions.messageThreshold, in: 4...100)
                    Stepper("或累计 \(editor.replyDraft.value.memoryOptions.characterThreshold) 字符", value: $editor.replyDraft.value.memoryOptions.characterThreshold, in: 1000...20000, step: 1000)
                    Stepper("或经过 \(editor.replyDraft.value.memoryOptions.intervalMinutes) 分钟", value: $editor.replyDraft.value.memoryOptions.intervalMinutes, in: 1...120)
                    Stepper("每轮检索最多 \(editor.replyDraft.value.memoryOptions.retrievalCharacters) 字符", value: $editor.replyDraft.value.memoryOptions.retrievalCharacters, in: 600...4000, step: 200)
                    Text(engine.memoryStatus).font(.caption)
                    Text("每群、每好友独立保存重点和待整理片段，暂停不丢失；群内保留说话人标识。只检索相关记忆，后台整理占模型额度。").font(.caption)
                    Stepper("配图至少间隔 \(editor.replyDraft.value.persona.stickerIntervalSeconds) 秒", value: $editor.replyDraft.value.persona.stickerIntervalSeconds, in: 1...3600)
                    Button("保存范围与回复草稿（不启动）") { saveReplyDraft() }
                    Text("本地精选 \(engine.stickerLibrary.items.count) 张，按配字和语境选图；同会话 24 小时不重复，重启保留记录，无合适图不硬配。群聊响应真实 @；主动接话须另行启用。").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $editor.replyDraft.value.ai.prompt).frame(height: 90).border(Color.secondary.opacity(0.2))
                    HStack {
                        Stepper("每日调用 \(editor.replyDraft.value.ai.dailyLimit)", value: $editor.replyDraft.value.ai.dailyLimit, in: 1...10000)
                        Stepper("单会话间隔 \(editor.replyDraft.value.ai.cooldownSeconds) 秒", value: $editor.replyDraft.value.ai.cooldownSeconds, in: 1...300)
                    }
                    HStack {
                        Stepper("每日发送 \(editor.replyDraft.value.ai.effectiveSendLimits.daily)", value: $editor.replyDraft.value.ai.effectiveSendLimits.daily, in: 1...10000)
                        Stepper("单会话每日 \(editor.replyDraft.value.ai.effectiveSendLimits.perChatDaily)", value: $editor.replyDraft.value.ai.effectiveSendLimits.perChatDaily, in: 1...10000)
                    }
                    Stepper("全局发送间隔 \(editor.replyDraft.value.ai.effectiveSendLimits.globalIntervalSeconds) 秒", value: $editor.replyDraft.value.ai.effectiveSendLimits.globalIntervalSeconds, in: 1...300)
                    Toggle("仅在指定时段回复", isOn: $editor.replyDraft.value.ai.workHoursEnabled)
                    if editor.replyDraft.value.ai.workHoursEnabled {
                        HStack {
                            Stepper("开始 \(editor.replyDraft.value.ai.workStart) 时", value: $editor.replyDraft.value.ai.workStart, in: 0...23)
                            Stepper("结束 \(editor.replyDraft.value.ai.workEnd) 时", value: $editor.replyDraft.value.ai.workEnd, in: 0...23)
                        }
                    }
                    Text("今日调用 \(engine.usage.calls) · 发送尝试 \(engine.sends.attempts) · 接口确认 \(engine.sends.confirmed) · 结果未知 \(engine.sends.uncertain)")
                    Text("本次规则拒绝 \(engine.rejectedScopedEvents) 个名单内消息事件（如未 @、不支持的消息或历史事件）").font(.caption).foregroundStyle(.secondary)
                    Text("草稿只在点击保存后生效；开始回复使用已保存配置。连接地址和令牌请断开后编辑。发送超时不会重发。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).disabled(engine.running)
            }
            }
            if editor.section == "记忆与记录" {
            DisclosureGroup("已保存的会话记忆") {
                ForEach(engine.memoryBooks.keys.filter { $0.hasPrefix(engine.config.expectedSelfID + ":") }.sorted(), id: \.self) { key in
                    if let book = engine.memoryBooks[key] {
                        Text("\(key)：\(book.items.filter { $0.current(Date()) }.count) 项记忆，\(book.pending.count) 条待整理，容量丢弃 \(book.droppedEvents) 条")
                        ForEach(book.items.filter { $0.current(Date()) }.suffix(32)) { item in Text("[\(item.subject)·\(item.kind)] \(item.text)").textSelection(.enabled) }
                    }
                }
            }
            if !engine.preview.isEmpty { GroupBox("本次回复预览（不落盘）") { Text(engine.preview).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) } }
            GroupBox("近期运行结果") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近 30 条，新记录在前。发送确认不代表对方已读；规则跳过不等于故障。记录不包含每条收到的消息，也不是回复质量验收。").font(.caption).foregroundStyle(.secondary)
                    if engine.runtimeRecords.isEmpty { Text("暂无处理结果。请核对连接、运行开关与已保存范围；群聊还需真实 @ 或已启用的主动接话。没有记录不代表没有收到消息。").font(.caption) }
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
            }
            }
        }.textFieldStyle(.roundedBorder)
        .onAppear { editor.refresh(engine.config) }
        .onChange(of: engine.config) { _, current in editor.refresh(current) }
    }
}
