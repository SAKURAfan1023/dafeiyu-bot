import SwiftUI
import UniformTypeIdentifiers
import BotCore

// macOS 27 CLT currently lacks SwiftUIMacros. Select the existing property-wrapper
// type explicitly instead of the newly overloaded @State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct BotApp: App {
    @StateObject private var engine: BotEngine
    @StateObject private var qq: QQEngine
    @StateObject private var social: SocialEngine
    @ViewState private var qqWebPanel: QQControlServer?
    private let preview = CommandLine.arguments.contains("--preview-panel")
    init() {
        let preview = CommandLine.arguments.contains("--preview-panel")
        _engine = StateObject(wrappedValue: BotEngine(preview: preview))
        _qq = StateObject(wrappedValue: QQEngine(preview: preview, allowAuthenticationUI: !preview))
        _social = StateObject(wrappedValue: SocialEngine(directory: preview ? FileManager.default.temporaryDirectory.appendingPathComponent("dafeiyu-social-preview-" + UUID().uuidString) : nil))
    }
    var body: some Scene {
        WindowGroup(preview ? "大肥鱼 · 面板预览" : "大肥鱼 · 控制台", id: "dashboard", content: {
            Dashboard(engine: engine, qq: qq, social: social, initialPage: CommandLine.arguments.contains("--xiaohongshu-view") ? .xhsConnect : .qq, openQQWebPanel: { openQQWebPanel() },
                      closeQQWebPanel: { closeQQWebPanel() }, webPanelOpen: qqWebPanel != nil)
                .frame(minWidth: 980, minHeight: 700)
                .onAppear {
                    if let image = PanelLogo.image { NSApp.applicationIconImage = image }
                    if preview { NSApp.activate(ignoringOtherApps: true) }
                    if CommandLine.arguments.contains("--xiaohongshu-view"), let panel = try? social.panel() {
                        print("XHS_CONTROL_URL=\(panel.controlURL.absoluteString)")
                    }
                }
        })
            .defaultSize(width: 1120, height: 780)
            .commands { PanelNavigationCommands() }
        MenuBarExtra("大肥鱼", systemImage: "bubble.left.and.text.bubble.right") {
            Text("微信：\(engine.status)")
            Text("QQ：\(qq.status)")
            Button(engine.isRunning || engine.isBusy ? "暂停微信操作" : "开始微信托管") { engine.isRunning || engine.isBusy ? engine.stop() : engine.start() }
                .disabled(!engine.isRunning && !engine.isBusy && engine.safetyReason != nil)
            Divider()
            ShowDashboardButton()
            Button("在浏览器打开 QQ 面板") { openQQWebPanel() }
            if qqWebPanel != nil { Button("关闭网页控制入口（不暂停 QQ）") { closeQQWebPanel() } }
            Text("小红书：\(social.status)")
            Button("暂停全部") { engine.stop(); qq.pause(); social.pause() }
            Button("退出") { engine.stop(); qq.disconnect(); social.shutdown(); NSApp.terminate(nil) }
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
    case overview = "总览", chats = "托管会话", ai = "AI 配置", rules = "回复规则", logs = "运行记录"
    case qq = "连接与运行", qqReply = "范围与回复", qqTools = "图片与工具", qqMemory = "记忆与记录"
    case xhsConnect = "账号与连接", xhsBrowse = "浏览与回复", xhsRecords = "草稿与记录"
    var id: String { rawValue }
    var qqSection: String? {
        switch self { case .qq, .qqReply, .qqTools, .qqMemory: return rawValue; default: return nil }
    }
    var xhsSection: String? {
        switch self { case .xhsConnect: return "connect"; case .xhsBrowse: return "browse"; case .xhsRecords: return "records"; default: return nil }
    }
    var icon: String {
        switch self { case .overview: return "square.grid.2x2"; case .chats: return "bubble.left.and.bubble.right"; case .ai: return "sparkles"; case .rules: return "slider.horizontal.3"; case .logs: return "list.bullet.rectangle"; case .qq: return "link"; case .qqReply: return "slider.horizontal.3"; case .qqTools: return "photo.on.rectangle"; case .qqMemory: return "clock.arrow.circlepath"; case .xhsConnect: return "person.crop.circle.badge.checkmark"; case .xhsBrowse: return "safari"; case .xhsRecords: return "square.and.pencil" }
    }
    var shortcut: KeyEquivalent {
        switch self { case .overview: return "1"; case .chats: return "2"; case .ai: return "3"; case .rules: return "4"; case .logs: return "5"; case .qq: return "6"; case .qqReply: return "7"; case .qqTools: return "8"; case .qqMemory: return "9"; case .xhsConnect: return "0"; case .xhsBrowse: return "b"; case .xhsRecords: return "d" }
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
    @ObservedObject var social: SocialEngine
    @ViewState private var page: Page = .qq
    @ViewState private var qqEditor = QQPanelState()
    @ViewState private var qqExpanded = true
    @ViewState private var wechatExpanded = true
    @ViewState private var xhsExpanded = true
    @ViewState private var key = ""
    @ViewState private var name = ""
    @ViewState private var kind: ChatKind = .direct
    @ViewState private var importing = false
    @ViewState private var confirmingUnlock = false
    @ViewState private var showingGuide = false
    private let openQQWebPanel: (() -> Void)?
    private let closeQQWebPanel: (() -> Void)?
    private let webPanelOpen: Bool
    private let accent = PanelTheme.accent
    private let ink = Color(red: 0.125, green: 0.145, blue: 0.12)
    private let mint = Color(red: 0.82, green: 0.95, blue: 0.60)
    init(engine: BotEngine, qq: QQEngine? = nil, social: SocialEngine? = nil, initialPage: Page = .qq,
         openQQWebPanel: (() -> Void)? = nil, closeQQWebPanel: (() -> Void)? = nil, webPanelOpen: Bool = false) {
        self.engine = engine; self.qq = qq ?? QQEngine(preview: true)
        self.social = social ?? SocialEngine(directory: FileManager.default.temporaryDirectory.appendingPathComponent("dafeiyu-social-preview-" + UUID().uuidString))
        self.openQQWebPanel = openQQWebPanel; self.closeQQWebPanel = closeQQWebPanel
        self.webPanelOpen = webPanelOpen
        _page = ViewState(initialValue: initialPage)
        var editor = QQPanelState(); editor.section = initialPage.qqSection ?? "连接与运行"
        _qqEditor = ViewState(initialValue: editor)
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    PanelLogo(size: 48).padding(3).background(mint, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("大肥鱼").font(.system(size: 23, weight: .bold)).foregroundStyle(.white)
                    }
                }.padding(.top, 24).padding(.horizontal, 17)
                ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    DisclosureGroup("QQ", isExpanded: $qqExpanded) {
                        ForEach(Page.allCases.filter { $0.qqSection != nil }) { item in
                            navigationRow(item)
                        }
                    }
                    DisclosureGroup("微信 · 测试中", isExpanded: $wechatExpanded) {
                        ForEach(Page.allCases.filter { $0.qqSection == nil && $0.xhsSection == nil }) { item in
                            navigationRow(item)
                        }
                    }
                    DisclosureGroup("小红书", isExpanded: $xhsExpanded) {
                        ForEach(Page.allCases.filter { $0.xhsSection != nil }) { item in navigationRow(item) }
                    }
                }.font(.caption).foregroundStyle(.white.opacity(0.72)).tint(.white.opacity(0.65))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }.scrollBounceBehavior(.basedOnSize).background(ink)
                VStack(alignment: .leading, spacing: 8) {
                    Button { showingGuide = true } label: {
                        Label("使用指南", systemImage: "book").font(.callout)
                    }.buttonStyle(.plain).foregroundStyle(.white).padding(.bottom, 12)
                    Label(engine.isRunning ? "微信托管中" : "微信已暂停", systemImage: engine.isRunning ? "circle.fill" : "pause.circle")
                        .foregroundStyle(engine.isRunning ? mint : .white.opacity(0.65))
                    Label(qq.running ? "QQ 托管中" : "QQ 已暂停", systemImage: qq.running ? "circle.fill" : "pause.circle")
                        .foregroundStyle(qq.running ? mint : .white.opacity(0.65))
                    Label(social.running ? "小红书浏览中" : "小红书已暂停", systemImage: social.running ? "circle.fill" : "pause.circle")
                        .foregroundStyle(social.running ? mint : .white.opacity(0.65))
                }.font(.caption2).padding(22)
            }.background(ink).navigationSplitViewColumnWidth(240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.rawValue).font(.system(size: 30, weight: .semibold)).tracking(-0.6)
                    }
                    Spacer()
                    if engine.isBusy { ProgressView().controlSize(.small) }
                    if page.qqSection != nil, let openQQWebPanel {
                        Menu {
                            Button("打开 QQ 网页版", action: openQQWebPanel)
                            if webPanelOpen, let closeQQWebPanel { Button("关闭网页控制入口", action: closeQQWebPanel) }
                        } label: { Label("网页版", systemImage: "arrow.up.right.square") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .help("网页与客户端共用 QQ 引擎；关闭网页入口不会暂停回复。")
                    }
                    Button { engine.stop(); qq.pause(); social.pause() } label: {
                        Label("暂停全部", systemImage: "pause.fill")
                    }.buttonStyle(PanelButtonStyle()).help("暂停微信、QQ 与小红书任务")

                    if page.qqSection == nil && page.xhsSection == nil { Button("开始微信托管") { engine.start() }.disabled(engine.isRunning || engine.isBusy || engine.safetyReason != nil) }
                }.padding(.horizontal, 32).padding(.vertical, 24)
                Rectangle().fill(PanelTheme.line).frame(height: 1)
                if let section = page.xhsSection { SocialView(engine: social, section: section) }
                else { ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if page.qqSection == nil, let reason = engine.safetyReason {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("微信自动操作已锁定", systemImage: "lock.shield").font(.headline)
                                Text(reason).textSelection(.enabled)
                                HelpHint("停机状态跨重启保留。AI 配置可编辑，诊断、验证与自测被阻止。")
                                Button("账号已核对，解除停机锁…") { confirmingUnlock = true }.disabled(engine.isBusy)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if page.qqSection == nil, let error = engine.error {
                            HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(error).textSelection(.enabled); Spacer(); Button("关闭") { engine.error = nil } }
                                .padding().background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        }
                        switch page {
                        case .overview: overview
                        case .chats: chats
                        case .ai: ai
                        case .rules: rules
                        case .logs: logs
                        case .qq, .qqReply, .qqTools, .qqMemory:
                            QQView(engine: qq, wechat: engine, editor: $qqEditor)
                        case .xhsConnect, .xhsBrowse, .xhsRecords: EmptyView()
                        }
                    }.padding(32)
                } }
            }.background(PanelTheme.canvas).foregroundStyle(PanelTheme.ink)
                .buttonStyle(PanelButtonStyle()).textFieldStyle(PanelTextFieldStyle())
                .controlSize(.large)
                .environment(\.colorScheme, .light)
        }.tint(accent)
            .onChange(of: page) { _, current in
                if let section = current.qqSection { qqEditor.section = section }
            }
            .focusedSceneValue(\.panelPage, $page)
            .sheet(isPresented: $showingGuide) {
                PanelGuideView { destination in
                    showingGuide = false
                    page = destination
                }
            }
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
    private func navigationRow(_ item: Page) -> some View {
        Button { page = item } label: {
            Label(item.rawValue, systemImage: item.icon)
                .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12)
                .foregroundStyle(page == item ? ink : .white.opacity(0.76))
                .background(page == item ? mint : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                stat("托管会话", "\(engine.config.chats.filter(\.enabled).count)", "最多 20 个", "person.2")
                stat("今日调用", "\(engine.usage.calls)", "上限 \(engine.config.dailyLimit) 次", "sparkles")
                stat("发送额度已用", "\(engine.sendUsage.attempts)", "上限 \(engine.config.effectiveSendLimits.daily) 次", "paperplane")
            }
            card("连接与验证", icon: "checklist", help: "配置 DeepSeek Key，授权辅助功能与屏幕录制，并打开微信。会话须使用唯一备注，验证后才能启用。托管时会切换微信窗口，手动聊天前请先暂停。群自动回复仍未通过验收。") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(engine.keyPresent ? "DeepSeek Key 已配置" : "DeepSeek Key 待验证", systemImage: engine.keyPresent ? "checkmark.circle.fill" : "1.circle")
                    Label("辅助功能与屏幕录制", systemImage: "2.circle")
                    Label("选择并验证会话", systemImage: "3.circle")
                    Label("群自动回复暂不可用", systemImage: "4.circle")
                }.font(.callout)
                HStack {
                    Button("报告账号异常并停机") { engine.recordSafetyStop() }
                    Button("请求系统权限") { engine.bridge.requestPermissions() }
                    Button("检查微信连接") { Task { await engine.inspect() } }.disabled(engine.isRunning || engine.isBusy || engine.safetyReason != nil)
                    Button("发送一条自测至文件助手") { Task { _ = await engine.selfTest() } }.disabled(engine.isRunning || engine.isBusy || !engine.keyPresent || engine.safetyReason != nil)
                }.padding(.top, 10)
            }
            card("微信连接诊断", icon: "stethoscope") { Text(engine.diagnostics).font(.system(.callout, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            card("最近回复预览", icon: "text.bubble") { Text(engine.preview.isEmpty ? "暂无回复" : engine.preview).foregroundStyle(engine.preview.isEmpty ? .secondary : .primary).textSelection(.enabled) }
        }
    }
    private var chats: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("添加会话", icon: "plus.bubble", help: "使用唯一备注；重名会话无法可靠定位。建议将托管会话置顶。") {
                HStack {
                    TextField("微信中的完整备注或群名称", text: $name)
                    Picker("类型", selection: $kind) { Text("好友").tag(ChatKind.direct); Text("群聊").tag(ChatKind.group) }.frame(width: 140)
                    Button("添加") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !engine.config.chats.contains(where: { $0.name == trimmed }), engine.config.chats.count < 20 else { engine.error = "名称不能为空或重复，且最多 20 个会话"; return }
                        engine.config.chats.append(ChatRule(name: trimmed, kind: kind)); name = ""
                    }.disabled(engine.isRunning)
                }

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
            HStack { Button("保存配置") { engine.save() }.buttonStyle(PanelButtonStyle(kind: .primary)); HelpHint("修改配置会暂停托管，重新开始后生效。未经验证的导入会话不会启用。") }
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
                TextEditor(text: $engine.config.prompt).frame(height: 150).modifier(PanelTextEditorStyle()).accessibilityLabel("全局角色提示词")
                PanelNumberField("最大输出", value: $engine.config.maxTokens, in: 100...2000, step: 100, unit: "tokens")
            }
            HStack { Button("保存配置") { engine.save() }.buttonStyle(PanelButtonStyle(kind: .primary)); Button("清空会话上下文") { engine.clearContext() } }
        }
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("自动回复规则", icon: "slider.horizontal.3", help: "发送前预留额度，结果未知不返还。额度不是账号安全阈值。工作时段使用本机时区，可跨午夜，起止相同表示全天。") {
                LabeledContent("私聊", value: "白名单中的新文字消息")
                LabeledContent("群聊", value: "逐条 @ 证据适配未完成 · 自动发送不可用")
                LabeledContent("运行方式", value: "自动发送 · 可随时暂停或人工接管")
                LabeledContent("连续消息", value: "等待 2 秒合并，最长 5 秒")
                PanelNumberField("单会话间隔", value: $engine.config.cooldownSeconds, in: 1...300, unit: "秒")
                PanelNumberField("每日模型调用上限", value: $engine.config.dailyLimit, in: 10...10000, step: 10, unit: "次")
                PanelNumberField("每日发送上限", value: $engine.config.effectiveSendLimits.daily, in: 1...10000, unit: "条")
                PanelNumberField("单会话每日发送上限", value: $engine.config.effectiveSendLimits.perChatDaily, in: 1...10000, unit: "条")
                PanelNumberField("全局发送间隔", value: $engine.config.effectiveSendLimits.globalIntervalSeconds, in: 1...300, unit: "秒")
                Toggle("仅在工作时段回复", isOn: $engine.config.workHoursEnabled)
                if engine.config.workHoursEnabled {
                    HStack { PanelNumberField("开始时间", value: $engine.config.workStart, in: 0...23, unit: "时"); PanelNumberField("结束时间", value: $engine.config.workEnd, in: 0...23, unit: "时") }
                }
            }
            card("本地数据", icon: "internaldrive", help: "截图不落盘。上下文只在内存保留最近 10 轮；运行记录保留 7 天，不含聊天正文或 Key。") {
                HStack {
                    Button("导出配置（不含 Key）") {
                        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "wechat-bot-config.json"
                        if panel.runModal() == .OK, let url = panel.url { do { try engine.exportConfig(to: url) } catch { engine.error = error.localizedDescription } }
                    }
                    Button("导入配置") { importing = true }.disabled(engine.isRunning)
                }
            }
            Button("保存配置") { engine.save() }.buttonStyle(PanelButtonStyle(kind: .primary))
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
            .frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
    private func card<Content: View>(_ title: String, icon: String, help: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { HStack { Label(title, systemImage: icon).font(.headline); if let help { HelpHint(help) } }; content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct QQCustomPersonaEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState private var draft: QQPersona
    @ViewState private var error: String?
    let apply: (QQPersona) throws -> Void
    init(persona: QQPersona, apply: @escaping (QQPersona) throws -> Void) {
        _draft = ViewState(initialValue: persona); self.apply = apply
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("自定义性格").font(.title2.bold())
            TextField("角色名称（最多 40 字）", text: Binding(get: { draft.customName ?? "" }, set: { draft.customName = $0 }))
            Text("性格 prompt").font(.headline)
            TextEditor(text: Binding(get: { draft.customPrompt ?? "" }, set: { draft.customPrompt = $0 }))
                .frame(minHeight: 180).modifier(PanelTextEditorStyle())
                .accessibilityLabel("性格 prompt")
            HStack {
                Button("简短闲聊") { draft.customPrompt = "你是轻松自然的聊天搭子，认真接住对方的话，通常一两句。可以接梗，但不写动作描写、不套客服语气。" }
                Button("温柔陪伴") { draft.customPrompt = "你是温柔耐心的陪伴者，先理解再回应，不说教、不强行安慰，不编造亲密关系。熟悉后可以轻轻开玩笑。" }
                Button("犀利吐槽") { draft.customPrompt = "你是嘴快但讲道理的游戏搭子，抓当前话题里的具体矛盾俏皮吐槽，承认自己答错；不攻击身份、身体或家人，认真求助时收起玩笑。" }
            }
            HStack {
                PanelNumberField("回复字数上限", value: $draft.maxCharacters, in: 20...200, unit: "字")
                Toggle("启用表情配图", isOn: $draft.stickersEnabled)
            }
            DisclosureGroup("可调整的范围") {
                Text("可自定角色名、身份设定、语气、称呼与互动偏好，prompt 最多 4000 字。应用只修改草稿，保存后生效；不会改变主人识别、会话名单、凭证或工具开关。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.orange).font(.callout) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("应用到草稿") {
                    do {
                        var value = draft; value.effectiveStyle = .custom
                        value.customName = value.customName?.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.customPrompt = value.customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
                        try value.validate(); try apply(value); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(PanelButtonStyle(kind: .primary))
            }
        }.padding(26).frame(width: 620).textFieldStyle(PanelTextFieldStyle()).buttonStyle(PanelButtonStyle())
            .background(PanelTheme.canvas)
    }
}

struct PanelGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let navigate: (Page) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PanelLogo(size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text("使用指南").font(.title.bold())
                    Text("先跑通一次回复，再开启其他功能。").foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    step(1, "登录 QQ", "启动 NapCat，扫码并在手机确认。开启 OneBot 正向 WebSocket，记下地址与令牌。已安装本项目 QQ 环境时，可在连接页启动环境和获取登录码。", destination: .qq, action: "去登录与连接")
                    step(2, "连接账号", "填写 OneBot 地址和机器人 QQ 号。首次使用可在上方填 OneBot Token，展开「临时凭证（本次运行）」填 DeepSeek Key，再点「使用临时凭证连接」。已有保存凭证时，保存连接设置后点「连接并核对账号」。", destination: .qq, action: "去连接账号")
                    step(3, "选谁可以收到回复", "从联系人列表添加好友或群，勾选启用，点「保存范围与回复」。群聊默认只在真正 @ 机器人时回复。", destination: .qqReply, action: "去选择会话")
                    step(4, "试一次，再正式运行", "点「试运行一次」，让已启用的好友发新消息，或在群里用 @ 选择器选中机器人。确认收到正常回复，再选时长并点「开始回复」。", destination: .qq, action: "去试运行")
                    step(5, "按喜好加功能", "在「范围与回复」调整性格和字数。图片、插画、定时在「图片与工具」各自配置保存，不用的功能可关闭。", destination: .qqTools, action: "设置图片工具")
                    Divider()
                    Text("遇到问题").font(.headline)
                    DisclosureGroup("已连接，为什么不回复？") {
                        Text("连接后还要开始回复。核对会话已勾选并保存、运行未到期、额度未用完。群内使用真正 @；主动接话达到条数只做评估，可能不接话。到「记忆与记录」查看处理结果。")
                    }
                    DisclosureGroup("如何修改配置或停止？") {
                        Text("先暂停，再修改并保存，然后重新开始。切页保留草稿，退出应用不保留未保存内容。关闭窗口或网页不会停止机器人，停止请点暂停。")
                    }
                    DisclosureGroup("凭证会保存吗？") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("临时凭证退出失效。长期使用可保存 OneBot Token 到钥匙串；DeepSeek Key 在「微信 → AI 配置」保存，QQ 共用该 Key。生图与搜图凭证独立配置。请勿分享凭证或控制链接。")
                            Button("配置共用 DeepSeek Key") { navigate(.ai) }
                        }
                    }
                    DisclosureGroup("微信怎么用？（测试中）") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("先在「AI 配置」保存 DeepSeek Key，开启辅助功能和屏幕录制权限。登录微信后添加并验证会话，勾选启用并保存，再开始托管。托管会切换微信窗口，手动聊天前先暂停。群自动回复暂不可用。")
                            Button("去微信总览") { navigate(.overview) }
                        }
                    }
                    Link("NapCat 安装教程 ↗", destination: URL(string: "https://napneko.github.io/guide/start-install")!)
                }.font(.callout).lineSpacing(5).padding(24)
            }
        }.frame(width: 690, height: 680).background(Color(red: 0.965, green: 0.965, blue: 0.94))
    }
    private func step(_ number: Int, _ title: String, _ instructions: String, destination: Page, action: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)").font(.headline).frame(width: 30, height: 30)
                .background(Color(red: 0.82, green: 0.95, blue: 0.60), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(instructions).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(action + " ↗") { navigate(destination) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HelpHint: View {
    let text: String
    @ViewState private var expanded = false
    init(_ text: String) { self.text = text }
    var body: some View {
        Button { expanded.toggle() } label: {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain).help(text).accessibilityLabel("功能说明")
        .popover(isPresented: $expanded) {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                .padding(16).frame(width: 320, alignment: .leading)
        }
    }
}

@MainActor struct PanelLogo: View {
    static let image = (RuntimeResources.directory?.appendingPathComponent("QQControl/logo.png")).flatMap { NSImage(contentsOf: $0) }
    var size: CGFloat = 48
    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
        }
    }
}
