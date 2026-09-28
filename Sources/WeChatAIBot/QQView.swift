import SwiftUI
import BotCore
private typealias QQViewState<Value> = SwiftUI.State<Value>

struct QQView: View {
    @ObservedObject var engine: QQEngine
    @ObservedObject var wechat: BotEngine
    @QQViewState private var token = ""
    @QQViewState private var webToken = ""
    @QQViewState private var temporaryKey = ""
    @QQViewState private var search = ""
    @QQViewState private var imageZhipuKey = ""
    @QQViewState private var imageCloudflareToken = ""
    @QQViewState private var persistImageCredentials = true
    @QQViewState private var googleVisionKey = ""
    @QQViewState private var persistVisualCredentials = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            QQArtworkSettingsView(engine: engine)
            GroupBox("QQ 连接 · NapCat / OneBot 11") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(engine.status).font(.headline)
                    Text("QQ 与 NapCat 在本机独立 Linux 环境运行，通过登录页扫码。微信与 QQ 独立启停。群聊响应真实 @，也可开启按消息数量主动接话。")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("OneBot 地址", text: $engine.config.endpoint).disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                    TextField("预期登录 QQ 号", text: $engine.config.expectedSelfID).disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                    SecureField("OneBot Access Token（留空保留已保存值）", text: $token).disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                    HStack {
                        Button("保存连接配置") { engine.save(token: token); if engine.error == nil { token = "" } }
                        Button("连接并核对账号") { Task { await engine.connect() } }
                        if (engine.busy || engine.runtimeBusy) { ProgressView().controlSize(.small) }
                    }.disabled(engine.connected || (engine.busy || engine.runtimeBusy))
                    DisclosureGroup("钥匙串不可用时：仅本次运行的凭证") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("在上方填写 OneBot 令牌，并在此填写 DeepSeek Key。临时凭证仅保留在当前进程内，退出后需重新输入；连接后仍需手动开始回复。")
                                .font(.caption).foregroundStyle(.secondary)
                            SecureField("仅本次运行的 DeepSeek Key", text: $temporaryKey)
                                .disabled(engine.connected || engine.busy || engine.runtimeBusy)
                            Button("使用临时凭证连接") {
                                guard engine.useTemporaryCredentials(token: token, key: temporaryKey) else { return }
                                token = ""; temporaryKey = ""
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
                    HStack {
                        Button(engine.running ? "暂停 QQ 自动回复" : "开始 QQ 自动回复") { engine.running ? engine.pause() : engine.start() }
                            .disabled(!engine.connected).buttonStyle(.borderedProminent)
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
                        SecureField("NapCat 管理令牌（已保存可留空）", text: $webToken)
                        Button("获取／刷新登录码") {
                            Task { await engine.refreshLoginCode(token: webToken); if engine.error == nil { webToken = "" } }
                        }
                    }.disabled(engine.connected || engine.busy || engine.runtimeBusy)
                    if let code = engine.loginCode {
                        Image(nsImage: code).interpolation(.none).resizable().frame(width: 280, height: 280)
                        Text("手机 QQ 扫码确认；二维码过期后请重新获取。登录本身不会开启自动回复。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(8)
            }
            if let error = engine.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            GroupBox("回复范围 · 最多 20 个会话") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($engine.config.targets) { $target in
                        HStack {
                            Toggle(isOn: $target.enabled) { Text("\(target.group ? "群" : "好友") · \(target.name) (\(target.number))") }.disabled(engine.running)
                            Picker("性格", selection: Binding(get: { target.personaStyle?.rawValue ?? "default" }, set: { engine.setPersonaStyle($0, target: target.key) })) {
                                Text("跟随默认").tag("default")
                                ForEach(QQPersonality.allCases, id: \.rawValue) { style in Text(style.name).tag(style.rawValue) }
                            }.frame(width: 150).disabled(engine.running || engine.busy || engine.runtimeBusy)
                            Button("接管") { engine.takeOver(target.id) }
                            Button("清除记忆并暂停") { engine.clearMemory(target.id) }
                            Button("移除") { engine.remove(target.id) }.disabled(engine.running)
                        }
                    }
                    Text(QQPersonaCommand.navigation + "。已启用群内无需 @，成员均可切换本群性格；暂停后可在面板调整。").font(.caption)
                    if engine.config.targets.isEmpty { Text("尚未添加。连接后从核对过的好友／群列表选择。默认全部禁用。") }
                    TextField("筛选联系人或群号", text: $search)
                    ForEach(engine.contacts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.number.contains(search) }.prefix(30)) { contact in
                        HStack {
                            Text("\(contact.group ? "群" : "好友") · \(contact.name) (\(contact.number))")
                            Spacer()
                            Button("添加到名单") { engine.add(contact) }.disabled(engine.running || engine.config.targets.contains { $0.key == contact.id })
                        }.font(.callout)
                    }
                    Text("列表最多显示 30 条，可输入 QQ 号／群号精确筛选。接管会暂停当前 QQ 队列并禁用该会话。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox("画图 · 双模型自动切换") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("启用 AI 生图（明确要求画图时调用）", isOn: $engine.config.effectiveImageGeneration.enabled)
                    Picker("默认模型", selection: $engine.config.effectiveImageGeneration.primary) {
                        ForEach(QQImageProvider.allCases, id: \.self) { provider in Text(provider.title).tag(provider) }
                    }
                    Toggle("默认失败后尝试另一个模型一次", isOn: $engine.config.effectiveImageGeneration.fallbackEnabled)
                    SecureField("智谱 API Key（留空保留）", text: $imageZhipuKey)
                    TextField("Cloudflare Account ID", text: $engine.config.effectiveImageGeneration.cloudflareAccountID)
                    SecureField("Cloudflare API Token（Workers AI 权限，留空保留）", text: $imageCloudflareToken)
                    Toggle("新填密钥保存至本机钥匙串（取消则仅本次运行）", isOn: $persistImageCredentials)
                    Text("智谱 \(engine.hasZhipuImageKey ? "已载入" : "未载入") · Cloudflare \(engine.hasCloudflareImageToken ? "已载入" : "未载入")；开始回复时会尝试读取已有钥匙串凭证。").font(.caption)
                    Button("保存生图配置（不启动回复）") {
                        engine.saveImageGeneration(engine.config.effectiveImageGeneration, zhipuKey: imageZhipuKey, cloudflareToken: imageCloudflareToken, persistCredentials: persistImageCredentials)
                        imageZhipuKey = ""; imageCloudflareToken = ""
                    }
                    Text(engine.imageGenerationStatus).font(.caption)
                    Text("直连两平台官方接口。每次最多生成一张；超时/限流/服务异常可切换，取消或审核拒绝不切换。请求计入每日模型调用限额。智谱固定免费 Flash；Cloudflare 请使用 Free 套餐，付费账户超额可能计费。").font(.caption).foregroundStyle(.secondary)
                }.padding(8).disabled(engine.running || engine.busy || engine.runtimeBusy)
            }
            GroupBox("识图与 Google 以图搜图") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("识图服务", selection: $engine.config.effectiveVisualTools.provider) {
                        ForEach(QQVisionProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("智谱复用生图区域的智谱 Key；主模型拥挤时最多切换一次免费 4.1V 备用。动图按时间最多取 6 帧，每轮最多 12 帧，再由 DeepSeek 理解对话。不保存原图。识图结果仍可能出错。").font(.caption)
                    Toggle("Google Web Detection（明确请求搜图/出处时）", isOn: $engine.config.effectiveVisualTools.googleWebEnabled)
                    SecureField("Google Cloud Vision API Key（留空保留）", text: $googleVisionKey)
                    Toggle("保存 Google Key 到钥匙串", isOn: $persistVisualCredentials)
                    Text(engine.hasGoogleVisionKey ? "Google 凭证已载入" : "Google 凭证未载入").font(.caption)
                    Link("开通 Cloud Vision API", destination: URL(string: "https://console.cloud.google.com/apis/library/vision.googleapis.com")!)
                    Text("还需启用识图与联网开关。仅提交一张缩图（动图代表帧），返回文字与来源链接，不回发搜图图片；调用占现有额度，Google 超免费额度可能计费。").font(.caption)
                    Button("保存识图设置（不启动回复）") {
                        engine.saveVisualTools(engine.config.effectiveVisualTools, googleKey: googleVisionKey, persistCredentials: persistVisualCredentials)
                        googleVisionKey = ""
                    }
                    Text(engine.visualStatus).font(.caption)
                }.padding(8).disabled(engine.running || engine.busy || engine.runtimeBusy)
            }
            GroupBox("QQ AI 与限额") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("使用 AI 配置页保存的 DeepSeek Key；QQ 的提示词、调用与发送额度独立统计。")
                    Text("高思考＋发送前语义校对：每条通常至少 2 次调用，生成可能更慢。私聊包含双方最近 20 条消息，区分 OWNER 主人、BOT 大肥鱼和 PEER 好友；来源不明的旧发言单独标记。").font(.caption)
                    HStack {
                        TextField("模型", text: $engine.config.ai.model)
                        Button("复制微信 AI 参数") {
                            var ai = wechat.config; ai.chats = []
                            ai.prompt = engine.config.ai.prompt; engine.config.ai = ai
                        }
                    }
                    Text("大肥鱼 · 成年鲸鱼娘同人角色。会话独立性格优先于默认；切换保留记忆与身份，下面填写补充偏好。").font(.caption)
                    Picker("默认性格", selection: $engine.config.effectivePersona.effectiveStyle) {
                        ForEach(QQPersonality.allCases, id: \.rawValue) { style in Text(style.name + " · " + style.description).tag(style) }
                    }
                    Stepper("回复最多 \(engine.config.effectivePersona.maxCharacters) 字符", value: $engine.config.effectivePersona.maxCharacters, in: 20...200)
                    Picker("雌小鬼嘴欠程度", selection: $engine.config.effectivePersona.banter) {
                        Text("温和").tag(0); Text("轻微吐槽").tag(1); Text("犀利但有分寸").tag(2); Text("锋利回怼").tag(3)
                    }
                    Toggle("定期配图，强烈情绪可提前配图", isOn: $engine.config.effectivePersona.stickersEnabled)
                    Stepper("每隔 \(engine.config.effectivePersona.effectiveStickerEveryReplies) 条回复配图（0 为仅强烈情绪）", value: $engine.config.effectivePersona.effectiveStickerEveryReplies, in: 0...10)
                    Text("达到条数后评估，适合才发；结合近期图片，分清主人与群成员，不抢答成员互聊。").font(.caption).foregroundStyle(.secondary)
                    Toggle("按群消息数量评估主动接话", isOn: $engine.config.effectiveGroupParticipationEnabled)
                    Stepper("每累计 \(engine.config.effectiveGroupParticipationEvery) 条群消息评估一次接话", value: $engine.config.effectiveGroupParticipationEvery, in: 1...1000)
                    Text("每群独立计数，包含本账号人工发言；自动回复、重复及历史消息不计入。真实 @ 独立回复，不计入也不重置普通消息进度；暂停清空计数和群聊片段。").font(.caption)
                    ForEach(engine.config.targets.filter { $0.enabled && $0.group }) { target in
                        Text("\(target.name)：\(engine.groupMessageCounts[target.key, default: 0]) / \(engine.config.effectiveGroupParticipationEvery) 条").font(.caption)
                    }
                    Toggle("允许搜索网页和网络图片", isOn: $engine.config.effectiveOnlineEnabled)
                    Toggle("识别图片和表情包（使用上方识图服务，不存原图）", isOn: $engine.config.effectiveVisionEnabled)
                    Toggle("独立会话记忆与自动压缩", isOn: $engine.config.effectiveMemoryEnabled)
                    Stepper("记忆每 \(engine.config.effectiveMemoryOptions.messageThreshold) 条整理", value: $engine.config.effectiveMemoryOptions.messageThreshold, in: 4...100)
                    Stepper("或累计 \(engine.config.effectiveMemoryOptions.characterThreshold) 字符", value: $engine.config.effectiveMemoryOptions.characterThreshold, in: 1000...20000, step: 1000)
                    Stepper("或经过 \(engine.config.effectiveMemoryOptions.intervalMinutes) 分钟", value: $engine.config.effectiveMemoryOptions.intervalMinutes, in: 1...120)
                    Stepper("每轮检索最多 \(engine.config.effectiveMemoryOptions.retrievalCharacters) 字符", value: $engine.config.effectiveMemoryOptions.retrievalCharacters, in: 600...4000, step: 200)
                    Text(engine.memoryStatus).font(.caption)
                    Text("每群、每好友独立保存重点和待整理片段，暂停不丢失；群内保留说话人标识。只检索相关记忆，后台整理占模型额度。").font(.caption)
                    Stepper("配图至少间隔 \(engine.config.effectivePersona.stickerIntervalSeconds) 秒", value: $engine.config.effectivePersona.stickerIntervalSeconds, in: 1...3600)
                    Button("保存回复设置（不启动）") { engine.saveReplySettings(ai: engine.config.ai, persona: engine.config.effectivePersona) }
                    Text("本地精选 \(engine.stickerLibrary.items.count) 张，按配字和语境选图；同会话 24 小时不重复，重启保留记录，无合适图不硬配。群聊响应真实 @；主动接话须另行启用。").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $engine.config.ai.prompt).frame(height: 90).border(Color.secondary.opacity(0.2))
                    HStack {
                        Stepper("每日调用 \(engine.config.ai.dailyLimit)", value: $engine.config.ai.dailyLimit, in: 1...10000)
                        Stepper("单会话间隔 \(engine.config.ai.cooldownSeconds) 秒", value: $engine.config.ai.cooldownSeconds, in: 1...300)
                    }
                    HStack {
                        Stepper("每日发送 \(engine.config.ai.effectiveSendLimits.daily)", value: $engine.config.ai.effectiveSendLimits.daily, in: 1...10000)
                        Stepper("单会话每日 \(engine.config.ai.effectiveSendLimits.perChatDaily)", value: $engine.config.ai.effectiveSendLimits.perChatDaily, in: 1...10000)
                    }
                    Stepper("全局发送间隔 \(engine.config.ai.effectiveSendLimits.globalIntervalSeconds) 秒", value: $engine.config.ai.effectiveSendLimits.globalIntervalSeconds, in: 1...300)
                    Toggle("仅在指定时段回复", isOn: $engine.config.ai.workHoursEnabled)
                    if engine.config.ai.workHoursEnabled {
                        HStack {
                            Stepper("开始 \(engine.config.ai.workStart) 时", value: $engine.config.ai.workStart, in: 0...23)
                            Stepper("结束 \(engine.config.ai.workEnd) 时", value: $engine.config.ai.workEnd, in: 0...23)
                        }
                    }
                    Text("今日调用 \(engine.usage.calls) · 发送尝试 \(engine.sends.attempts) · 接口确认 \(engine.sends.confirmed) · 结果未知 \(engine.sends.uncertain)")
                    Text("本次规则拒绝 \(engine.rejectedScopedEvents) 个名单内消息事件（如未 @、不支持的消息或历史事件）").font(.caption).foregroundStyle(.secondary)
                    Text("修改在下一次启动 QQ 托管前保存；连接地址和令牌请断开后编辑。发送超时不会重发。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).disabled(engine.running)
            }
            DisclosureGroup("已保存的会话记忆") {
                ForEach(engine.memoryBooks.keys.filter { $0.hasPrefix(engine.config.expectedSelfID + ":") }.sorted(), id: \.self) { key in
                    if let book = engine.memoryBooks[key] {
                        Text("\(key)：\(book.items.filter { $0.current(Date()) }.count) 项记忆，\(book.pending.count) 条待整理，容量丢弃 \(book.droppedEvents) 条")
                        ForEach(book.items.filter { $0.current(Date()) }.suffix(32)) { item in Text("[\(item.subject)·\(item.kind)] \(item.text)").textSelection(.enabled) }
                    }
                }
            }
            if !engine.preview.isEmpty { GroupBox("本次回复预览（不落盘）") { Text(engine.preview).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) } }
            GroupBox("QQ 运行记录（仅元数据）") {
                VStack(alignment: .leading, spacing: 8) {
                    if engine.logs.isEmpty { Text("暂无 QQ 回复记录") }
                    ForEach(engine.logs.reversed().prefix(30)) { item in
                        Text("\(item.date.formatted(date: .omitted, time: .standard)) · \(item.state.rawValue) · \(item.detail)").font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }.textFieldStyle(.roundedBorder)
    }
}
