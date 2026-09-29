import SwiftUI
import UniformTypeIdentifiers
import BotCore

// macOS 27 CLT currently lacks SwiftUIMacros. Select the existing property-wrapper
// type explicitly instead of the newly overloaded @State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct BotApp: App {
    @StateObject private var engine = BotEngine()
    @StateObject private var qq = QQEngine()
    @ViewState private var qqWebPanel: QQControlServer?
    var body: some Scene {
        WindowGroup("微信与 QQ AI 助手", id: "dashboard", content: {
            Dashboard(engine: engine, qq: qq, openQQWebPanel: { openQQWebPanel() },
                      closeQQWebPanel: { closeQQWebPanel() }, webPanelOpen: qqWebPanel != nil)
                .frame(minWidth: 980, minHeight: 700)
        })
            .defaultSize(width: 1120, height: 780)
            .commands { PanelNavigationCommands() }
        MenuBarExtra("微信与 QQ AI 助手", systemImage: "bubble.left.and.text.bubble.right") {
            Text("微信：\(engine.status)")
            Text("QQ：\(qq.status)")
            Button(engine.isRunning || engine.isBusy ? "暂停微信操作" : "开始微信托管") { engine.isRunning || engine.isBusy ? engine.stop() : engine.start() }
                .disabled(!engine.isRunning && !engine.isBusy && engine.safetyReason != nil)
            Divider()
            ShowDashboardButton()
            Button("在浏览器打开 QQ 面板") { openQQWebPanel() }
            if qqWebPanel != nil { Button("关闭网页控制入口（不暂停 QQ）") { closeQQWebPanel() } }
            Button("暂停微信与 QQ") { engine.stop(); qq.pause() }
            Button("退出") { engine.stop(); qq.disconnect(); NSApp.terminate(nil) }
        }
    }
    @MainActor private func openQQWebPanel() {
        do {
            let server: QQControlServer
            if let existing = qqWebPanel { server = existing }
            else {
                server = try QQControlServer(engine: qq)
                server.start(announce: false); qqWebPanel = server
            }
            if !NSWorkspace.shared.open(server.controlURL) { qq.error = "无法打开默认浏览器，请检查本机浏览器设置。网页控制入口仍可关闭后重试。" }
        } catch { qq.error = error.localizedDescription }
    }
    @MainActor private func closeQQWebPanel() { qqWebPanel?.stop(); qqWebPanel = nil }
}
private struct ShowDashboardButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("显示面板") {
            if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "dashboard")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
enum Page: String, CaseIterable, Identifiable {
    case overview = "总览", chats = "托管会话", ai = "AI 配置", rules = "回复规则", logs = "运行记录", qq = "QQ 接入"
    var id: String { rawValue }
    var icon: String {
        switch self { case .overview: return "square.grid.2x2"; case .chats: return "bubble.left.and.bubble.right"; case .ai: return "sparkles"; case .rules: return "slider.horizontal.3"; case .logs: return "list.bullet.rectangle"; case .qq: return "bubble.left.fill" }
    }
    var shortcut: KeyEquivalent {
        switch self { case .overview: return "1"; case .chats: return "2"; case .ai: return "3"; case .rules: return "4"; case .logs: return "5"; case .qq: return "6" }
    }
}
private struct PanelPageKey: FocusedValueKey { typealias Value = Binding<Page> }
private extension FocusedValues {
    var panelPage: Binding<Page>? {
        get { self[PanelPageKey.self] }
        set { self[PanelPageKey.self] = newValue }
    }
}
private struct PanelNavigationCommands: Commands {
    @FocusedBinding(\.panelPage) private var page: Page?
    var body: some Commands {
        CommandMenu("面板导航") {
            ForEach(Page.allCases) { item in
                Button(item.rawValue) { page = item }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
                    .disabled(page == nil)
            }
        }
    }
}
struct Dashboard: View {
    @ObservedObject var engine: BotEngine
    @ObservedObject var qq: QQEngine
    @ViewState private var page: Page = .overview
    @ViewState private var qqEditor = QQPanelState()
    @ViewState private var key = ""
    @ViewState private var name = ""
    @ViewState private var kind: ChatKind = .direct
    @ViewState private var importing = false
    @ViewState private var confirmingUnlock = false
    private let openQQWebPanel: (() -> Void)?
    private let closeQQWebPanel: (() -> Void)?
    private let webPanelOpen: Bool
    private let accent = Color(red: 0.10, green: 0.47, blue: 0.39)
    init(engine: BotEngine, qq: QQEngine? = nil, initialPage: Page = .overview,
         openQQWebPanel: (() -> Void)? = nil, closeQQWebPanel: (() -> Void)? = nil, webPanelOpen: Bool = false) {
        self.engine = engine; self.qq = qq ?? QQEngine(preview: true)
        self.openQQWebPanel = openQQWebPanel; self.closeQQWebPanel = closeQQWebPanel
        self.webPanelOpen = webPanelOpen
        _page = ViewState(initialValue: initialPage)
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.title).foregroundStyle(accent)
                    VStack(alignment: .leading) { Text("微信与 QQ AI 助手").font(.headline); Text("本机托管 · DeepSeek").font(.caption).foregroundStyle(.secondary) }
                }.padding(.top, 24).padding(.horizontal, 16)
                List(Page.allCases, selection: $page) { item in Label(item.rawValue, systemImage: item.icon).tag(item).padding(.vertical, 6) }
                VStack(alignment: .leading, spacing: 8) {
                    Label(engine.isRunning ? "微信托管中" : "微信已暂停", systemImage: engine.isRunning ? "circle.fill" : "pause.circle")
                        .foregroundStyle(engine.isRunning ? accent : .secondary)
                    Label(qq.running ? "QQ 托管中" : "QQ 已暂停", systemImage: qq.running ? "circle.fill" : "pause.circle")
                    Text("微信本地识别 · QQ 本机接口\n持久保存的密钥位于钥匙串").font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text(page.rawValue).font(.largeTitle.bold()); Text(page == .qq ? qq.status : engine.status).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                    if engine.isBusy { ProgressView().controlSize(.small) }
                    Button { engine.stop(); qq.pause() } label: {
                        Label("暂停微信与 QQ", systemImage: "pause.fill").padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).tint(engine.isRunning ? .orange : accent)
                        
                    if page != .qq { Button("开始微信托管") { engine.start() }.disabled(engine.isRunning || engine.isBusy || engine.safetyReason != nil) }
                }.padding(28)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if page != .qq, let reason = engine.safetyReason {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("微信自动操作已锁定", systemImage: "lock.shield").font(.headline)
                                Text(reason).textSelection(.enabled)
                                Text("停机状态会跨重启保留。AI 配置仍可编辑；诊断、验证与自测均已阻止。")
                                Button("账号已核对，解除停机锁…") { confirmingUnlock = true }.disabled(engine.isBusy)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let error = engine.error {
                            HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(error).textSelection(.enabled); Spacer(); Button("关闭") { engine.error = nil } }
                                .padding().background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        }
                        switch page {
                        case .overview: overview
                        case .chats: chats
                        case .ai: ai
                        case .rules: rules
                        case .logs: logs
                        case .qq:
                            if let openQQWebPanel {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Button("在浏览器打开 QQ 面板", action: openQQWebPanel)
                                        if webPanelOpen, let closeQQWebPanel { Button("关闭网页控制入口", action: closeQQWebPanel) }
                                    }
                                    Text("网页与本窗口共用同一 QQ 引擎。关闭网页入口不会暂停回复；需要停止时请使用暂停按钮。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            QQView(engine: qq, wechat: engine, editor: $qqEditor)
                        }
                    }.padding(28)
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }.tint(accent)
            .focusedSceneValue(\.panelPage, $page)
            .confirmationDialog("确认已在微信中核对账号状态并决定恢复接入？", isPresented: $confirmingUnlock) {
                Button("解除停机锁，不启动托管", role: .destructive) { engine.clearSafetyStop() }
                Button("保持停机", role: .cancel) { }
            } message: {
                Text("解除后所有会话仍保持禁用，需要重新验证。此操作不能保证账号不会再次受限。")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; try engine.importConfig(from: url) }
                catch { engine.error = error.localizedDescription }
            }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                stat("托管会话", "\(engine.config.chats.filter(\.enabled).count)", "最多 20 个", "person.2")
                stat("今日调用", "\(engine.usage.calls)", "上限 \(engine.config.dailyLimit) 次", "sparkles")
                stat("发送额度已用", "\(engine.sendUsage.attempts)", "上限 \(engine.config.effectiveSendLimits.daily) 次", "paperplane")
            }
            card("首次使用", icon: "checklist") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(engine.keyPresent ? "DeepSeek Key 已配置" : "请在 AI 配置中测试已保存的 Key，或配置新 Key", systemImage: engine.keyPresent ? "checkmark.circle.fill" : "1.circle")
                    Label("授权辅助功能与屏幕录制，并运行微信主窗口", systemImage: "2.circle")
                    Label("添加唯一名称的好友或群，验证后启用并保存", systemImage: "3.circle")
                    Label("先验证私聊；群逐条 @ 识别尚未完成，暂不可启用群自动发送", systemImage: "4.circle")
                }.font(.callout)
                HStack {
                    Button("报告账号异常并停机") { engine.recordSafetyStop() }
                    Button("请求系统权限") { engine.bridge.requestPermissions() }
                    Button("检查微信连接") { Task { await engine.inspect() } }.disabled(engine.isRunning || engine.isBusy || engine.safetyReason != nil)
                    Button("发送一条自测至文件助手") { Task { _ = await engine.selfTest() } }.disabled(engine.isRunning || engine.isBusy || !engine.keyPresent || engine.safetyReason != nil)
                }.padding(.top, 10)
            }
            card("微信连接诊断", icon: "stethoscope") { Text(engine.diagnostics).font(.system(.callout, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            card("最近回复预览", icon: "text.bubble") { Text(engine.preview.isEmpty ? "尚无回复。仅显示本次运行产生的内容，退出后清空。" : engine.preview).foregroundStyle(engine.preview.isEmpty ? .secondary : .primary).textSelection(.enabled) }
            Text("托管时程序会切换微信窗口。需要手动聊天时请先暂停。锁屏、休眠或微信退出后需要重新开始。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var chats: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("添加会话", icon: "plus.bubble") {
                HStack {
                    TextField("微信中的完整备注或群名称", text: $name)
                    Picker("类型", selection: $kind) { Text("好友").tag(ChatKind.direct); Text("群聊").tag(ChatKind.group) }.frame(width: 140)
                    Button("添加") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !engine.config.chats.contains(where: { $0.name == trimmed }), engine.config.chats.count < 20 else { engine.error = "名称不能为空或重复，且最多 20 个会话"; return }
                        engine.config.chats.append(ChatRule(name: trimmed, kind: kind)); name = ""
                    }.disabled(engine.isRunning)
                }
                Text("使用唯一备注；重名会话不能可靠自动定位。建议将托管会话置顶，以便捕获未读和 @ 提示。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($engine.config.chats) { $rule in
                card(rule.name, icon: rule.kind == .group ? "person.3" : "person") {
                    HStack {
                        Label(rule.bound ? "已验证" : "尚未验证", systemImage: rule.bound ? "checkmark.seal" : "questionmark.circle").foregroundStyle(.secondary)
                        Spacer()
                        Toggle("启用", isOn: $rule.enabled).toggleStyle(.switch).disabled(engine.isRunning || (!rule.enabled && (!rule.bound || rule.kind == .group)))
                        Button("验证会话") { Task { await engine.bind(rule.id) } }.disabled(engine.isRunning || engine.isBusy || engine.safetyReason != nil)
                        Button("人工接管") { engine.takeOver(rule.id) }.disabled(!engine.isRunning)
                        Button(role: .destructive) { engine.config.chats.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }.disabled(engine.isRunning)
                    }
                    if rule.kind == .group {
                        TextField("本账号在该群的昵称（识别 @ 使用）", text: $rule.selfName).disabled(engine.isRunning)
                        Text("会话定位可验证；逐条真正 @ 尚无可靠适配，群自动发送暂不可用。").font(.caption).foregroundStyle(.orange)
                    }
                    TextField("专属角色提示词（留空沿用全局）", text: $rule.prompt, axis: .vertical).lineLimit(2...5).disabled(engine.isRunning)
                }
            }
            HStack { Button("保存配置") { engine.save() }.buttonStyle(.borderedProminent); Text("修改配置会暂停托管，重新开始后生效。未经验证的导入会话不会自动启用。").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var ai: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("DeepSeek 连接", icon: "key") {
                Text("官方接口 · https://api.deepseek.com").font(.callout).foregroundStyle(.secondary)
                HStack { SecureField(engine.keyPresent ? "已保存；输入新 Key 可替换" : "输入新 Key，或测试已保存的 Key", text: $key); Button("存入钥匙串") { engine.saveKey(key); key = "" }.disabled(key.isEmpty) }
                HStack { Button("测试连接并读取模型") { Task { await engine.testConnection() } }.disabled(engine.isBusy || engine.isRunning); Text(engine.keyPresent ? "本机已保存 Key" : "本次尚未验证钥匙串访问").foregroundStyle(.secondary) }
                TextField("模型 ID", text: $engine.config.model)
                if !engine.availableModels.isEmpty { Text("可用模型：" + engine.availableModels.joined(separator: "、")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            card("回复风格", icon: "text.alignleft") {
                Text("全局角色提示词").font(.headline)
                TextEditor(text: $engine.config.prompt).font(.body).frame(height: 150).scrollContentBackground(.hidden)
                Stepper("最大输出：\(engine.config.maxTokens) tokens", value: $engine.config.maxTokens, in: 100...2000, step: 100)
            }
            HStack { Button("保存配置") { engine.save() }.buttonStyle(.borderedProminent); Button("清空会话上下文") { engine.clearContext() } }
        }
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("自动回复规则", icon: "slider.horizontal.3") {
                LabeledContent("私聊", value: "白名单中的新文字消息")
                LabeledContent("群聊", value: "逐条 @ 证据适配未完成 · 自动发送不可用")
                LabeledContent("运行方式", value: "自动发送 · 可随时暂停或人工接管")
                LabeledContent("连续消息", value: "等待 2 秒合并，最长 5 秒")
                Stepper("每个会话冷却：\(engine.config.cooldownSeconds) 秒", value: $engine.config.cooldownSeconds, in: 1...300)
                Stepper("每日 API 请求上限：\(engine.config.dailyLimit) 次", value: $engine.config.dailyLimit, in: 10...10000, step: 10)
                Stepper("每日发送额度：\(engine.config.effectiveSendLimits.daily) 次", value: $engine.config.effectiveSendLimits.daily, in: 1...10000)
                Stepper("单会话每日发送额度：\(engine.config.effectiveSendLimits.perChatDaily) 次", value: $engine.config.effectiveSendLimits.perChatDaily, in: 1...10000)
                Stepper("全局发送间隔：\(engine.config.effectiveSendLimits.globalIntervalSeconds) 秒", value: $engine.config.effectiveSendLimits.globalIntervalSeconds, in: 1...300)
                Text("发送前预留额度并落盘；结果未知不返还。额度与间隔用于控制操作量，不是微信安全阈值。").font(.caption).foregroundStyle(.secondary)
                Toggle("仅在工作时段回复", isOn: $engine.config.workHoursEnabled)
                if engine.config.workHoursEnabled {
                    HStack { Stepper("开始：\(engine.config.workStart):00", value: $engine.config.workStart, in: 0...23); Stepper("结束：\(engine.config.workEnd):00", value: $engine.config.workEnd, in: 0...23) }
                    Text("使用本机时区，支持跨午夜；开始和结束相同表示全天。").font(.caption).foregroundStyle(.secondary)
                }
            }
            card("本地数据", icon: "internaldrive") {
                Text("截图不落盘。对话上下文只在内存中保留最近 10 轮。运行记录不包含聊天正文或 Key，保留 7 天。")
                HStack {
                    Button("导出配置（不含 Key）") {
                        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "wechat-bot-config.json"
                        if panel.runModal() == .OK, let url = panel.url { do { try engine.exportConfig(to: url) } catch { engine.error = error.localizedDescription } }
                    }
                    Button("导入配置") { importing = true }.disabled(engine.isRunning)
                }
            }
            Button("保存配置") { engine.save() }.buttonStyle(.borderedProminent)
        }
    }
    private var logs: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("调用 \(engine.usage.calls) 次 · 返回用量 \(engine.usage.tokens) tokens").font(.headline); Spacer(); Text("最近 200 条").foregroundStyle(.secondary) }
            Text("发送预留 \(engine.sendUsage.attempts) 次 · 本机回显 \(engine.sendUsage.confirmed) 次 · 未确认 \(engine.sendUsage.uncertain) 次 · 待处理 \(engine.queueCount) 项").font(.callout).foregroundStyle(.secondary)
            if engine.logs.isEmpty { ContentUnavailableView("还没有运行记录", systemImage: "tray", description: Text("开始托管后，会在这里显示每一步的实际状态。")) }
            ForEach(Array(engine.logs.suffix(200).reversed())) { item in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.state == .confirmed ? "checkmark.circle.fill" : item.state == .failed || item.state == .uncertain ? "exclamationmark.circle" : "circle.dotted")
                        .foregroundStyle(item.state == .confirmed ? accent : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.detail).textSelection(.enabled)
                        Text((engine.config.chats.first(where: { $0.id == item.chatID })?.name ?? "系统") + " · " + item.date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private func stat(_ label: String, _ value: String, _ detail: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) { Label(label, systemImage: icon).foregroundStyle(.secondary); Text(value).font(.system(size: 32, weight: .semibold, design: .rounded)); Text(detail).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { Label(title, systemImage: icon).font(.headline); content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}
