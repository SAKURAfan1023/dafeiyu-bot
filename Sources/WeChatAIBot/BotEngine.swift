import AppKit
import Combine
import BotCore

@MainActor final class BotEngine: ObservableObject {
    @Published var config = BotConfig()
    @Published var usage = Usage()
    @Published var sendUsage = SendUsage()
    @Published var logs: [LogEntry] = []
    @Published var status = "已暂停"
    @Published var isRunning = false
    @Published var isBusy = false
    @Published var error: String?
    @Published var keyPresent = false
    @Published var availableModels: [String] = []
    @Published var diagnostics = "尚未检查"
    @Published var queueCount = 0
    @Published var preview = ""
    @Published private(set) var safetyReason: String?
    let bridge = WeChatBridge()
    private let client = DeepSeekClient()
    private var store: LocalStore?
    private var storageHealthy = true
    private var savedConfig = BotConfig()
    private var fence = RunFence()
    private var monitor: Task<Void, Never>?
    private var generators: [UUID: Task<Void, Never>] = [:]
    private var baselines: [UUID: [ObservedMessage]] = [:]
    private var history: [UUID: [ChatTurn]] = [:]
    private var signals: [String: String] = [:]
    private var pausedChats: Set<UUID> = []
    private var systemObservers: [NSObjectProtocol] = []
    private struct Pending {
        var texts: [String]; var first = Date(); var due = Date().addingTimeInterval(2)
    }
    private struct Outgoing {
        var rule: ChatRule; var input: String; var result: ModelResult; var epoch: UInt64; var created = Date()
    }
    private var pending: [UUID: Pending] = [:]
    private var outbox: [Outgoing] = []

    init(preview: Bool = false) {
        if preview {
            // Render-only fixtures: no credentials, local configuration, observers or WeChat access.
            storageHealthy = false
            safetyReason = "离线界面预览 · 未连接真实微信"
            status = "离线界面预览"
            config.chats = [ChatRule(name: "测试好友", bound: true), ChatRule(name: "测试群", kind: .group, selfName: "测试昵称")]
            logs = [LogEntry(state: .cancelled, detail: "示例记录：点击暂停后，排队回复已取消")]
            return
        }
        do {
            let s = try LocalStore(); store = s
            let state = try s.load(); config = state.config; savedConfig = state.config; usage = state.usage; logs = state.logs; sendUsage = state.sendUsage ?? SendUsage()
        } catch { storageHealthy = false; self.error = "配置读取失败，未覆盖原文件：\(error.localizedDescription)" }
        // Do not request credentials during window creation: a locked keychain can
        // wait for authentication indefinitely. Explicit save/test/start checks access.
        refreshSafetyState()
        systemObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(reason: "系统休眠，已暂停；唤醒后请重新开始") }
        })
        systemObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(reason: "用户会话不再活跃，已暂停") }
        })
    }
    private func refreshSafetyState() {
        do { safetyReason = try bridge.interlock.currentStop()?.reason }
        catch { safetyReason = "停机记录无法读取，自动操作已阻止：" + error.localizedDescription }
        if safetyReason != nil { status = "安全停机 · 微信自动操作已锁定" }
    }
    func recordSafetyStop() {
        stop(reason: "用户报告账号异常，已停止操作")
        do { try bridge.interlock.trip(reason: "用户报告账号异常，需人工核对微信提示后恢复") }
        catch { self.error = "停机记录保存失败：" + error.localizedDescription }
        refreshSafetyState()
    }
    func clearSafetyStop() {
        guard !isRunning, !isBusy else { return }
        do {
            for index in config.chats.indices { config.chats[index].bound = false; config.chats[index].enabled = false }
            savedConfig = config; try persist()
            try bridge.interlock.clear()
            refreshSafetyState()
            status = "已解除停机锁，尚未启动；请重新验证会话"
        } catch { self.error = error.localizedDescription; refreshSafetyState() }
    }
    func save() {
        do {
            try config.validate()
            stop(reason: "配置已更新，请重新开始托管")
            savedConfig = config; try persist()
        } catch { self.error = error.localizedDescription }
    }
    func saveKey(_ text: String) {
        do { try Keychain.save(text); keyPresent = true; status = "Key 已保存到本机钥匙串" }
        catch { self.error = error.localizedDescription }
    }
    func testConnection() async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do {
            availableModels = try await client.models(key: Keychain.load())
            keyPresent = true
            if !availableModels.contains(config.model), let first = availableModels.first {
                config.model = availableModels.contains("deepseek-chat") ? "deepseek-chat" : first
            }
            status = "DeepSeek 已连接，读取到 \(availableModels.count) 个模型"
        } catch { self.error = error.localizedDescription }
    }
    func inspect() async {
        guard !isRunning, !isBusy else { return }
        isBusy = true; defer { isBusy = false; bridge.stopObserving(); refreshSafetyState() }
        do {
            try bridge.prepare()
            let frame = try await bridge.capture(force: true)
            diagnostics = "微信：\(bridge.applicationPath)\n辅助功能：\(bridge.accessibility ? "已授权" : "未授权")\n屏幕读取：\(bridge.screenCapture ? "已授权" : "未授权")\n主窗口：\(Int(frame.size.width)) × \(Int(frame.size.height))\n当前聊天：\((try? bridge.title(in: frame)) ?? "未选中或无法识别")\n识别文本块：\(frame.lines.count)\n截图仅在内存中处理"
        } catch {
            diagnostics = "辅助功能：\(bridge.accessibility)；屏幕录制：\(bridge.screenCapture)；微信：\(bridge.running)\n\(error.localizedDescription)"
            self.error = error.localizedDescription
        }
    }
    func bind(_ id: UUID) async {
        guard !isRunning, !isBusy, let index = config.chats.firstIndex(where: { $0.id == id }) else { return }
        isBusy = true; fence.start(); let epoch = fence.epoch
        defer { fence.stop(); isBusy = false; bridge.stopObserving(); refreshSafetyState() }
        do {
            var rule = config.chats[index]
            let frame = try await bridge.select(rule, valid: { self.allowed(epoch) })
            let snapshot = try await bridge.snapshot(rule: rule, frame: frame)
            guard !snapshot.messages.isEmpty else { throw AppFailure.message("聊天已定位，但未读到可核对的消息；请在微信中打开有文字记录的聊天后重试") }
            rule.bound = true; config.chats[index] = rule
            status = "已验证「\(rule.name)」；请开启会话开关并保存"
            diagnostics = "读取模式：\(bridge.lastMode)；消息块 \(snapshot.messages.count)；收到 \(snapshot.messages.filter { $0.direction == .incoming }.count)；发出 \(snapshot.messages.filter { $0.direction == .outgoing }.count)；方向未知 \(snapshot.messages.filter { $0.direction == .unknown }.count)"
        } catch { self.error = error.localizedDescription }
    }
    func start() {
        guard !isRunning, !isBusy else { return }
        do {
            try bridge.interlock.requireClear()
            try config.validate()
            guard storageHealthy else { throw AppFailure.message("存储不可用，请先解决配置文件错误") }
            guard !(try Keychain.load()).isEmpty else { throw AppFailure.message("请先保存并测试 DeepSeek Key") }
            guard !config.chats.contains(where: { $0.enabled && $0.kind == .group }) else {
                throw AppFailure.message("当前适配器尚不能核对逐条真正 @，群聊自动发送不可用；请先停用群开关并保留配置")
            }
            guard config.chats.contains(where: { $0.enabled }) else { throw AppFailure.message("请至少验证并启用一个托管会话") }
            try bridge.prepare()
            savedConfig = config; try persist()
            fence.start(); isRunning = true; let epoch = fence.epoch
            baselines = [:]; signals = [:]; history = [:]; pausedChats = []; pending = [:]; outbox = []
            monitor = Task { await run(epoch: epoch) }
        } catch { self.error = error.localizedDescription }
    }
    func stop(reason: String = "已暂停；未提交的回复已取消") {
        fence.stop(); isRunning = false; monitor?.cancel()
        for task in generators.values { task.cancel() }
        generators = [:]; pending = [:]; outbox = []; queueCount = 0
        bridge.stopObserving(); status = reason
    }
    func takeOver(_ id: UUID) {
        pausedChats.insert(id); generators[id]?.cancel(); generators[id] = nil
        pending[id] = nil; outbox.removeAll { $0.rule.id == id }
        log(id, .cancelled, "已人工接管；重新开始托管后恢复")
    }
    func clearContext() { history = [:]; preview = ""; status = "本轮上下文已清空" }
    /// Explicit smoke test to the user's own built-in chat. It is not an inbound-message test.
    func selfTest() async -> Bool {
        guard !isRunning, !isBusy else { return false }
        isBusy = true; fence.start(); let epoch = fence.epoch
        defer { fence.stop(); isBusy = false; bridge.stopObserving(); refreshSafetyState() }
        let id = savedConfig.chats.first(where: { $0.name == "文件传输助手" })?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let rule = ChatRule(id: id, name: "文件传输助手", enabled: true, bound: true)
        var reservation: UUID?
        do {
            try bridge.prepare()
            let result = try await client.reply(key: Keychain.load(), config: savedConfig, rule: rule, history: [],
                text: "这是微信机器人软件的连通性测试。请只回复以下文字，不要加引号：微信 AI 助手连接成功。", reserve: { [weak self] in
                    try await self?.reserve(epoch: epoch, id: rule.id)
                })
            usage.tokens += result.tokens; preview = result.text
            log(nil, .sending, "自测：向文件传输助手发送一条 AI 生成的连接测试消息")
            let receipt = try await bridge.send(result.text, rule: rule, valid: { self.allowed(epoch) }, beforeSubmit: {
                reservation = try self.reserveSend(epoch: epoch, id: rule.id)
            })
            let confirmed = receipt.confirmed
            if let reservation { sendUsage.finish(reservation, confirmed: confirmed) }
            log(nil, confirmed ? .confirmed : .uncertain, confirmed ? "文件传输助手出现新增本机回显；不代表对端送达，好友入站及群 @ 尚需验收" : "文件传输助手发送结果不确定，不会重发")
            status = confirmed ? "自发测试成功（不等于好友／群自动回复已验收）" : "自发测试待核对"
            return confirmed
        } catch {
            if let reservation { sendUsage.finish(reservation, confirmed: false) }
            self.error = error.localizedDescription
            log(nil, reservation == nil ? .failed : .uncertain, "自发测试未完成：\(error.localizedDescription)")
            return false
        }
    }
    private func allowed(_ epoch: UInt64, _ id: UUID? = nil) -> Bool {
        fence.permits(epoch) && (id == nil || !pausedChats.contains(id!))
    }
    private func run(epoch: UInt64) async {
        isBusy = true
        defer { isBusy = false; refreshSafetyState() }
        do {
            let rules = savedConfig.chats.filter(\.enabled)
            for (index, rule) in rules.enumerated() {
                guard allowed(epoch) else { throw CancellationError() }
                status = "建立基线 \(index + 1)/\(rules.count)：\(rule.name)"
                let frame = try await bridge.select(rule, valid: { self.allowed(epoch) })
                let snap = try await bridge.snapshot(rule: rule, frame: frame)
                guard !snap.messages.isEmpty else { throw AppFailure.message("「\(rule.name)」未读到消息，无法建立基线") }
                baselines[rule.id] = snap.messages
                for signal in bridge.signals(in: frame, rules: rules) { signals[signal.name] = signal.signature }
            }
            status = "正在托管 · 事件触发＋闲时补查 · \(rules.count) 个会话"
            var lastSweep = ProcessInfo.processInfo.systemUptime
            var schedule = ReadSchedule(), lastFingerprint: String?
            while allowed(epoch) {
                try Task.checkCancellation()
                guard bridge.accessibility, bridge.screenCapture, bridge.running, !bridge.locked, bridge.frontmost else {
                    throw AppFailure.message("微信、权限、焦点或屏幕状态变化，已暂停")
                }
                let now = ProcessInfo.processInfo.systemUptime
                if schedule.isDue(now: now, event: bridge.changed) {
                    bridge.changed = false
                    var frame = try await bridge.capture()
                    schedule.didRead(now: ProcessInfo.processInfo.systemUptime, changed: lastFingerprint != frame.fingerprint)
                    lastFingerprint = frame.fingerprint
                    var candidates: Set<UUID> = []
                    let visible = bridge.signals(in: frame, rules: rules)
                    for signal in visible {
                        if signals[signal.name] != signal.signature,
                           let rule = rules.first(where: { $0.name == signal.name }) { candidates.insert(rule.id) }
                        signals[signal.name] = signal.signature
                    }
                    diagnostics = "已注册 AX 通知 \(bridge.registeredEvents) 类；当前列表可见 \(visible.count)/\(rules.count) 个目标；闲时补查最长 8 秒"
                    if let title = try? bridge.title(in: frame), let rule = rules.first(where: { $0.name == title }) {
                        candidates.insert(rule.id)
                    }
                    if now - lastSweep >= 60, outbox.isEmpty, visible.count < rules.count {
                        try await sweep(rules: rules, epoch: epoch, candidates: &candidates)
                        lastSweep = ProcessInfo.processInfo.systemUptime
                        frame = try await bridge.capture()
                    }
                    for id in candidates where !pausedChats.contains(id) {
                        guard allowed(epoch, id), let rule = rules.first(where: { $0.id == id }) else { continue }
                        if (try? bridge.title(in: frame)) != rule.name {
                            frame = try await bridge.select(rule, valid: { self.allowed(epoch, id) })
                        }
                        let snapshot = try await bridge.snapshot(rule: rule, frame: frame)
                        accept(snapshot, rule: rule)
                    }
                }
                if savedConfig.inWorkHours() { launchGenerators(epoch: epoch, rules: rules) }
                else { pending = [:]; outbox = []; status = "工作时段外 · 只更新基线" }
                if let outgoing = outbox.first {
                    if !allowed(outgoing.epoch, outgoing.rule.id) || !savedConfig.inWorkHours() || Date().timeIntervalSince(outgoing.created) >= 120 {
                        outbox.removeFirst(); log(outgoing.rule.id, .cancelled, "回复已过期或已暂停")
                    } else {
                        switch sendUsage.allowance(chat: outgoing.rule.id, limits: savedConfig.effectiveSendLimits, chatCooldown: savedConfig.cooldownSeconds) {
                        case .allowed: outbox.removeFirst(); try await deliver(outgoing)
                        case .cooldown: break
                        case .globalLimit: stop(reason: "今日发送额度已用完")
                        case .chatLimit: takeOver(outgoing.rule.id)
                        }
                    }
                }
                queueCount = pending.count + generators.count + outbox.count
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription; log(nil, .failed, error.localizedDescription); stop(reason: "已暂停：\(error.localizedDescription)") }
    }
    private func sweep(rules: [ChatRule], epoch: UInt64, candidates: inout Set<UUID>) async throws {
        var seen: Set<String> = []
        var scrolls = 0
        for _ in 0..<6 {
            guard allowed(epoch) else { throw CancellationError() }
            let frame = try await bridge.capture(force: true)
            for signal in bridge.signals(in: frame, rules: rules) {
                seen.insert(signal.name)
                if signals[signal.name] != signal.signature, let rule = rules.first(where: { $0.name == signal.name }) {
                    candidates.insert(rule.id)
                }
                signals[signal.name] = signal.signature
            }
            if seen.count == rules.count { break }
            try bridge.scrollSidebar(in: frame, down: true); scrolls += 1
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        // Bounded list scan. Missing names are not guessed and not auto-opened.
        if seen.count < rules.count { diagnostics = "本次列表补扫可见 \(seen.count)/\(rules.count) 个目标；不可见会话可能延迟，请将托管会话置顶。" }
        let frame = try await bridge.capture(force: true)
        for _ in 0..<scrolls {
            guard allowed(epoch) else { throw CancellationError() }
            try bridge.scrollSidebar(in: frame, down: false)
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }
    private func accept(_ snapshot: ChatSnapshot, rule: ChatRule, confirmedReply: String? = nil) {
        let previous = baselines[rule.id] ?? []
        baselines[rule.id] = snapshot.messages
        switch MessagePolicy.delta(previous: previous, current: snapshot.messages) {
        case .unchanged: return
        case .resync: log(rule.id, .skipped, "消息快照失去连续性，重建基线并跳过，防止回复旧消息")
        case .appended(let messages):
            for message in messages {
                if message.direction == .outgoing {
                    if let confirmedReply, SendVerification.matches(expected: confirmedReply, observed: message.text, ocr: bridge.lastMode == "本地 OCR") { continue }
                    takeOver(rule.id); continue
                }
                if let reason = MessagePolicy.rejection(message, rule: rule) { log(rule.id, .skipped, reason); continue }
                guard !pausedChats.contains(rule.id), savedConfig.inWorkHours() else { continue }
                if var batch = pending[rule.id] {
                    batch.texts.append(message.text); batch.due = min(Date().addingTimeInterval(2), batch.first.addingTimeInterval(5)); pending[rule.id] = batch
                } else { pending[rule.id] = Pending(texts: [message.text]) }
                log(rule.id, .queued, "新文字消息通过规则，等待合并")
            }
        }
    }
    private func launchGenerators(epoch: UInt64, rules: [ChatRule]) {
        for (id, batch) in pending.sorted(by: { $0.value.first < $1.value.first }) {
            guard generators.count < 2 else { break }
            guard batch.due <= Date(), generators[id] == nil, !outbox.contains(where: { $0.rule.id == id }),
                  allowed(epoch, id), let rule = rules.first(where: { $0.id == id }) else { continue }
            switch sendUsage.allowance(chat: id, limits: savedConfig.effectiveSendLimits, chatCooldown: savedConfig.cooldownSeconds) {
            case .globalLimit: stop(reason: "今日发送额度已用完"); return
            case .chatLimit: takeOver(id); continue
            case .cooldown: continue
            case .allowed: break
            }
            pending[id] = nil
            let text = batch.texts.joined(separator: "\n"), config = savedConfig, context = history[id] ?? []
            log(id, .generating, "正在生成回复")
            generators[id] = Task { [weak self] in
                guard let self else { return }
                defer { if self.fence.epoch == epoch { self.generators[id] = nil } }
                do {
                    let key = try Keychain.load()
                    let result = try await self.client.reply(key: key, config: config, rule: rule, history: context, text: text, reserve: { [weak self] in
                        try await self?.reserve(epoch: epoch, id: id)
                    })
                    self.usage.tokens += result.tokens; try self.persist()
                    guard self.allowed(epoch, id) else { return }
                    self.preview = "\(rule.name)\n\(result.text)"
                    self.outbox.append(Outgoing(rule: rule, input: text, result: result, epoch: epoch))
                } catch is CancellationError { }
                catch {
                    self.log(id, .failed, error.localizedDescription)
                    if let http = error as? HTTPFailure, [401, 402].contains(http.code) { self.stop(reason: error.localizedDescription) }
                    self.error = error.localizedDescription
                }
            }
        }
    }
    private func reserve(epoch: UInt64, id: UUID) throws {
        guard allowed(epoch, id) else { throw CancellationError() }
        guard usage.reserve(limit: savedConfig.dailyLimit) else {
            stop(reason: "今日调用上限已到，请调整限额或明日继续")
            throw AppFailure.message("每日调用上限已到")
        }
        try persist()
    }
    private func reserveSend(epoch: UInt64, id: UUID) throws -> UUID {
        guard allowed(epoch, id), savedConfig.inWorkHours() else { throw CancellationError() }
        let ticket = try sendUsage.reserve(chat: id, limits: savedConfig.effectiveSendLimits, chatCooldown: savedConfig.cooldownSeconds)
        do { try persist() }
        catch { sendUsage.finish(ticket, confirmed: false); throw error }
        return ticket
    }
    private func deliver(_ outgoing: Outgoing) async throws {
        let rule = outgoing.rule
        log(rule.id, .sending, "准备发送；正在复核窗口和输入框")
        var reservation: UUID?
        do {
            let receipt = try await bridge.send(outgoing.result.text, rule: rule, valid: {
                self.allowed(outgoing.epoch, rule.id) && self.savedConfig.inWorkHours() && Date().timeIntervalSince(outgoing.created) < 120
            }, observeBeforeTyping: { self.accept($0, rule: rule) }, beforeSubmit: {
                reservation = try self.reserveSend(epoch: outgoing.epoch, id: rule.id)
            })
            let confirmed = receipt.confirmed
            if let reservation { sendUsage.finish(reservation, confirmed: confirmed) }
            if confirmed {
                history[rule.id, default: []].append(ChatTurn(incoming: outgoing.input, outgoing: outgoing.result.text))
                history[rule.id] = Array((history[rule.id] ?? []).suffix(10))
                log(rule.id, .confirmed, "本机聊天已出现回复；模型耗时 \(String(format: "%.1f", outgoing.result.seconds)) 秒")
            } else { log(rule.id, .uncertain, "已尝试发送，但未确认本机回显；不会自动重发"); takeOver(rule.id) }
            accept(receipt.snapshot, rule: rule, confirmedReply: confirmed ? outgoing.result.text : nil)
        } catch {
            if let reservation { sendUsage.finish(reservation, confirmed: false) }
            log(rule.id, reservation == nil ? .failed : .uncertain, "发送未完成：\(error.localizedDescription)；不会重发")
            takeOver(rule.id)
            throw error
        }
    }
    private func persist() throws {
        guard storageHealthy, let store else { throw AppFailure.message("本地存储不可用") }
        try store.save(StoredState(config: savedConfig, usage: usage, logs: logs, sendUsage: sendUsage))
    }
    private func log(_ id: UUID?, _ state: JobState, _ detail: String) {
        logs.append(LogEntry(chatID: id, state: state, detail: detail)); logs = Array(logs.suffix(5000))
        do { try persist() } catch { storageHealthy = false; self.error = "运行记录无法落盘，已暂停：\(error.localizedDescription)"; stop(reason: "存储失败") }
    }
    func exportConfig(to url: URL) throws { try JSONEncoder().encode(config).write(to: url, options: .atomic) }
    func importConfig(from url: URL) throws {
        guard !isRunning else { throw AppFailure.message("请先暂停") }
        var value = try JSONDecoder().decode(BotConfig.self, from: Data(contentsOf: url))
        for i in value.chats.indices { value.chats[i].enabled = false; value.chats[i].bound = false }
        try value.validate(); config = value; save()
    }
}
