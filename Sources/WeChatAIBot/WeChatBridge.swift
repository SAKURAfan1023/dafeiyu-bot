import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import CryptoKit
import BotCore

struct TextBox {
    let text: String
    let rect: CGRect // Window-local, top-left origin, in points.
    let confidence: Float
}
struct WindowFrame {
    let window: SCWindow
    let image: CGImage
    let lines: [TextBox]
    let fingerprint: String
    var size: CGSize { window.frame.size }
}
struct ChatSignal: Equatable {
    let name: String
    let signature: String
}
struct ChatSnapshot {
    let title: String
    let messages: [ObservedMessage]
    let frame: WindowFrame
}

struct SendReceipt {
    let confirmed: Bool
    let snapshot: ChatSnapshot
}

/// All UI access is confined to one main-actor bridge, owned by the engine.
@MainActor final class WeChatBridge {
    let interlock = automationInterlock()
    private var suspended = true
    private var observer: AXObserver?
    private var observedPID: pid_t?
    var changed = true
    private(set) var registeredEvents = 0
    var lastMode = "未检测"
    private var cachedFrame: WindowFrame?
    private var cachedDigest = ""
    private var sidebarWidth: CGFloat = 300
    private var ocrInputRect: CGRect?
    private var app: NSRunningApplication? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.xinWeChat")
        return apps.count == 1 ? apps.first : nil
    }
    var accessibility: Bool { AXIsProcessTrusted() }
    var screenCapture: Bool { CGPreflightScreenCaptureAccess() }
    var running: Bool { app != nil }
    var applicationPath: String { app?.bundleURL?.path ?? "未找到唯一运行中的微信" }
    var frontmost: Bool { app?.isActive ?? false }
    var locked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
    func requestPermissions() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        CGRequestScreenCaptureAccess()
    }
    func prepare() throws {
        try interlock.requireClear()
        try Task.checkCancellation()
        guard accessibility else { throw AppFailure.message("需要辅助功能权限") }
        guard let app else { throw AppFailure.message("请只运行一个微信实例，并完成登录") }
        guard !locked else { throw AppFailure.message("屏幕已锁定") }
        if suspended { app.unhide(); app.activate(options: []) }
        else if !frontmost { throw AppFailure.message("微信失去焦点，已暂停；不会抢回窗口") }
        if observedPID != app.processIdentifier {
            stopObserving()
            var next: AXObserver?
            let callback: AXObserverCallback = { _, _, _, context in
                guard let context else { return }
                let bridge = Unmanaged<WeChatBridge>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in bridge.changed = true }
            }
            if AXObserverCreate(app.processIdentifier, callback, &next) == .success, let next {
                let root = AXUIElementCreateApplication(app.processIdentifier)
                let ptr = Unmanaged.passUnretained(self).toOpaque()
                for event in [kAXValueChangedNotification, kAXLayoutChangedNotification, kAXFocusedUIElementChangedNotification, kAXWindowCreatedNotification] {
                    if AXObserverAddNotification(next, root, event as CFString, ptr) == .success { registeredEvents += 1 }
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(next), .commonModes)
                observer = next; observedPID = app.processIdentifier
            }
        }
        suspended = false
    }
    func stopObserving() {
        suspended = true
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; observedPID = nil; cachedFrame = nil; cachedDigest = ""; registeredEvents = 0
    }
    private func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func string(_ element: AXUIElement, _ name: String) -> String { attr(element, name) as? String ?? "" }
    private func find(_ root: AXUIElement, depth: Int = 0, matching: (AXUIElement) -> Bool) -> [AXUIElement] {
        guard depth < 25 else { return [] }
        var result = matching(root) ? [root] : []
        for child in attr(root, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            result += find(child, depth: depth + 1, matching: matching)
        }
        return result
    }
    private func axWindow() throws -> AXUIElement {
        guard let app else { throw AppFailure.message("微信未运行") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windows = attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let main = windows.filter { ["微信", "WeChat"].contains(string($0, kAXTitleAttribute)) }
        if main.count == 1 { return main[0] }
        guard windows.count == 1 else { throw AppFailure.message("无法确定微信主窗口，请关闭分离聊天或弹窗") }
        return windows[0]
    }
    private func rect(_ element: AXUIElement) -> CGRect? {
        guard let p = attr(element, kAXPositionAttribute), let s = attr(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point); AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
    private func inputElement() -> AXUIElement? {
        guard let window = try? axWindow() else { return nil }
        let matches = find(window) { string($0, kAXIdentifierAttribute) == "chat_input_field" }
        return matches.count == 1 ? matches[0] : nil
    }
    func capture(force: Bool = false) async throws -> WindowFrame {
        try requireActive()
        let started = Date()
        let trace = CommandLine.arguments.contains("--diagnose")
        guard !locked, let app else { throw AppFailure.message("微信退出或屏幕锁定") }
        guard screenCapture else { throw AppFailure.message("需要屏幕录制权限以读取微信窗口") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try requireActive()
        if trace { print("窗口枚举耗时 \(Date().timeIntervalSince(started))s") }
        let matches = content.windows.filter {
            $0.owningApplication?.processID == app.processIdentifier && $0.frame.width > 500 && $0.frame.height > 350
        }
        let main = matches.filter { ["微信", "WeChat"].contains($0.title ?? "") }
        let selected = main.count == 1 ? main : matches
        guard selected.count == 1 else {
            try interlock.trip(reason: "微信窗口结构改变或主窗口不可用，请核对登录状态及弹窗")
            throw AppFailure.message("无法确定唯一微信主窗口，已锁定自动操作")
        }
        let window = selected[0]
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try requireActive()
        if trace { print("截图累计耗时 \(Date().timeIntervalSince(started))s") }
        // Hash a small thumbnail; no full OCR when the window pixels did not change.
        let digest = thumbnailDigest(image)
        if !force, digest == cachedDigest, let cached = cachedFrame, cached.window.windowID == window.windowID,
           cached.window.frame == window.frame { return WindowFrame(window: window, image: image, lines: cached.lines, fingerprint: digest) }
        let size = window.frame.size
        let lines = try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.usesCPUOnly = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { item -> TextBox? in
                guard let text = item.topCandidates(1).first else { return nil }
                let b = item.boundingBox
                return TextBox(text: text.string,
                    rect: CGRect(x: b.minX * size.width, y: (1 - b.maxY) * size.height, width: b.width * size.width, height: b.height * size.height),
                    confidence: text.confidence)
            }.sorted { $0.rect.minY < $1.rect.minY }
        }.value
        try requireActive()
        // Inspect non-chat screens conservatively; never continue after a login/security screen.
        let hasSearch = lines.contains { ["搜索", "Search"].contains($0.text) && $0.rect.minY < 75 && $0.rect.midX < window.frame.width * 0.48 }
        let markers = ["扫码登录", "扫描二维码登录", "登录环境异常", "使用外挂", "帐号存在安全风险", "账号存在安全风险", "已退出登录", "Log in to WeChat", "Scan QR Code"]
        if !hasSearch && lines.contains(where: { line in markers.contains { line.text.contains($0) } }) {
            try interlock.trip(reason: "检测到登录或安全提示界面，请在微信中核对账号状态")
            throw AppFailure.message("微信登录状态异常，已锁定自动操作")
        }
        let frame = WindowFrame(window: window, image: image, lines: lines, fingerprint: digest)
        if trace { print("OCR 累计耗时 \(Date().timeIntervalSince(started))s") }
        cachedFrame = frame; cachedDigest = digest
        detectLayout(frame)
        return frame
    }
    private func thumbnailDigest(_ image: CGImage) -> String {
        var data = [UInt8](repeating: 0, count: 160 * 120 * 4)
        guard let ctx = CGContext(data: &data, width: 160, height: 120, bitsPerComponent: 8, bytesPerRow: 640,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return UUID().uuidString }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 120))
        return SHA256.hash(data: Data(data)).map { String(format: "%02x", $0) }.joined()
    }
    private func detectLayout(_ frame: WindowFrame) {
        // The search bar bounds are used when exposed; otherwise use the visible separator.
        if let window = try? axWindow(), let search = find(window, matching: {
            ["Search", "搜索"].contains(string($0, kAXTitleAttribute))
        }).first, let r = rect(search) {
            sidebarWidth = min(frame.size.width * 0.48, max(220, r.maxX - frame.window.frame.minX + 24))
        } else {
            sidebarWidth = findVerticalDivider(frame) ?? min(300, frame.size.width * 0.34)
        }
        ocrInputRect = CGRect(x: sidebarWidth + 16, y: frame.size.height * 0.77,
                             width: frame.size.width - sidebarWidth - 32, height: frame.size.height * 0.16)
    }
    private func findVerticalDivider(_ frame: WindowFrame) -> CGFloat? {
        // Search for a long, uniform divider in the expected sidebar range.
        let image = frame.image, scale = CGFloat(image.width) / frame.size.width
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let bpp = image.bitsPerPixel / 8, stride = image.bytesPerRow
        guard bpp >= 3 else { return nil }
        var best: (Int, Int) = (0, 0)
        let low = Int(220 * scale), high = min(image.width - 2, Int(min(420, frame.size.width * 0.48) * scale))
        guard low < high else { return nil }
        for x in low..<high {
            var score = 0
            for y in strideValue(Int(100 * scale), Int((frame.size.height - 40) * scale), Int(max(2, 8 * scale))) {
                let a = y * stride + (x - 1) * bpp, b = y * stride + (x + 1) * bpp
                let difference = abs(Int(bytes[a]) - Int(bytes[b])) + abs(Int(bytes[a + 1]) - Int(bytes[b + 1])) + abs(Int(bytes[a + 2]) - Int(bytes[b + 2]))
                if difference > 6 { score += 1 }
            }
            if score > best.1 { best = (x, score) }
        }
        return best.1 > 20 ? CGFloat(best.0) / scale : nil
    }
    private func strideValue(_ start: Int, _ end: Int, _ step: Int) -> [Int] { Array(Swift.stride(from: start, to: end, by: step)) }
    func title(in frame: WindowFrame) throws -> String {
        if let window = try? axWindow() {
            let titles = find(window) { string($0, kAXIdentifierAttribute) == "big_title_line_h_view" }
            if titles.count == 1 {
                let value = string(titles[0], kAXValueAttribute)
                if !value.isEmpty { return normalizeTitle(value) }
            }
        }
        let candidates = frame.lines.filter { $0.rect.minX > sidebarWidth + 10 && $0.rect.minY > 10 && $0.rect.minY < 70 && $0.confidence >= 0.85 }
        guard let first = candidates.first else { throw AppFailure.message("无法读取当前聊天标题") }
        return normalizeTitle(first.text)
    }
    private func normalizeTitle(_ name: String) -> String {
        name.replacingOccurrences(of: "[（(][0-9]+[)）]$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func signals(in frame: WindowFrame, rules: [ChatRule]) -> [ChatSignal] {
        let pixels = PixelMap(frame.image, size: frame.size)
        return rules.compactMap { rule in
            let matches = frame.lines.filter { line in
                guard line.rect.midX < sidebarWidth, line.confidence >= 0.9 else { return false }
                if line.text == rule.name { return true }
                guard line.text.hasSuffix("…") || line.text.hasSuffix("...") else { return false }
                let prefix = line.text.replacingOccurrences(of: "[.…]+$", with: "", options: .regularExpression)
                return prefix.count >= 3 && rule.name.hasPrefix(prefix) && rules.filter { $0.name.hasPrefix(prefix) }.count == 1
            }
            guard matches.count == 1, let row = matches.first else { return nil }
            let nearby = frame.lines.filter { $0.rect.midX < sidebarWidth && $0.rect.minY >= row.rect.minY - 3 && $0.rect.minY < row.rect.minY + 47 }
            let text = nearby.map(\.text).joined(separator: "|")
            let unread = pixels?.redCount(in: CGRect(x: 65, y: row.rect.minY - 12, width: 44, height: 30)) ?? 0
            return ChatSignal(name: rule.name, signature: text + "|unread:\(unread / 8)")
        }
    }
    func scrollSidebar(in frame: WindowFrame, down: Bool) throws {
        try assertAvailable(frame)
        let p = CGPoint(x: frame.window.frame.minX + sidebarWidth / 2, y: frame.window.frame.minY + frame.size.height / 2)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: down ? -400 : 400, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }
    func select(_ rule: ChatRule, valid: () -> Bool) async throws -> WindowFrame {
        guard valid() else { throw CancellationError() }
        try prepare()
        var frame = try await capture(force: true)
        guard valid() else { throw CancellationError() }
        if rule.bound, (try? title(in: frame)) == rule.name { return frame }
        if ["文件传输助手", "File Transfer"].contains(rule.name) {
            let rows = frame.lines.filter { $0.text == rule.name && $0.rect.midX < sidebarWidth && $0.confidence >= 0.9 }
            if rows.count == 1 {
                try click(rows[0].rect.center, frame: frame)
                try await Task.sleep(nanoseconds: 400_000_000)
                frame = try await capture(force: true)
                guard valid(), try title(in: frame) == rule.name else { throw AppFailure.message("文件传输助手定位未通过复核") }
                return frame
            }
        }
        // Search explicitly; names in the sidebar are not globally unique.
        if let window = try? axWindow(), let search = find(window, matching: {
            ["Search", "搜索"].contains(string($0, kAXTitleAttribute)) && string($0, kAXRoleAttribute) == kAXTextAreaRole
        }).first {
            try assertAvailable(frame)
            AXUIElementSetAttributeValue(search, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(search, kAXValueAttribute as CFString, rule.name as CFString)
        } else {
            let search = frame.lines.filter { ["搜索", "Search"].contains($0.text) && $0.rect.midX < sidebarWidth && $0.rect.minY < 75 }
            guard search.count == 1 else { throw AppFailure.message("无法准确定位微信搜索框") }
            try click(search[0].rect.center, frame: frame)
            try key(0, flags: .maskCommand); try typeUnicode(rule.name)
        }
        try await Task.sleep(nanoseconds: 600_000_000)
        guard valid() else { throw CancellationError() }
        frame = try await capture(force: true)
        let sectionNames = rule.kind == .group ? ["群聊", "Group Chats"] : ["联系人", "Contacts", "最常使用", "最近使用", "聊天", "Chats"]
        let headings = frame.lines.filter { ["联系人", "Contacts", "群聊", "Group Chats", "聊天记录", "Chat History", "公众号", "Official Accounts", "最常使用", "最近使用", "聊天", "Chats"].contains($0.text) && $0.rect.minX < sidebarWidth }
        let exact = frame.lines.filter { line in
            guard line.text == rule.name, line.confidence >= 0.9, line.rect.minY > 65, line.rect.minX < sidebarWidth else { return false }
            let heading = headings.filter { $0.rect.minY < line.rect.minY }.last
            return heading.map { sectionNames.contains($0.text) } ?? false
        }
        guard exact.count == 1 else {
            guard valid() else { throw CancellationError() }
            try key(53)
            throw AppFailure.message("搜索没有唯一匹配的\(rule.kind == .group ? "群聊" : "联系人")；请使用唯一备注，勿使用重名")
        }
        guard valid() else { throw CancellationError() }
        try click(exact[0].rect.center, frame: frame)
        try await Task.sleep(nanoseconds: 400_000_000)
        frame = try await capture(force: true)
        guard valid(), try title(in: frame) == rule.name else { throw AppFailure.message("选择后聊天标题不匹配，已停止操作") }
        return frame
    }
    func snapshot(rule: ChatRule, frame providedFrame: WindowFrame? = nil) async throws -> ChatSnapshot {
        let frame: WindowFrame
        if let provided = providedFrame { frame = provided } else { frame = try await capture(force: true) }
        let name = try title(in: frame)
        guard name == rule.name else { throw AppFailure.message("聊天标题与目标不一致") }
        try requireActive()
        var messages = axMessages(frame: frame)
        if messages.isEmpty { lastMode = "本地 OCR"; messages = ocrMessages(frame: frame) }
        else { lastMode = "辅助功能＋窗口校验" }
        // A sidebar badge cannot identify which message contains a genuine mention.
        // Keep text-only evidence until a per-message adapter has been verified.
        let mentioned = messages.indices.filter {
            messages[$0].direction == .incoming && MessagePolicy.hasMentionText(messages[$0].text, selfName: rule.selfName)
                && !messages[$0].text.contains("引用") && !messages[$0].text.contains("「")
        }
        if rule.kind == .group {
            for index in mentioned { messages[index].mention = .textOnly }
        }
        return ChatSnapshot(title: name, messages: messages, frame: frame)
    }
    private func axMessages(frame: WindowFrame) -> [ObservedMessage] {
        guard let window = try? axWindow() else { return [] }
        let lists = find(window) { string($0, kAXRoleAttribute) == kAXListRole && ["消息", "Messages"].contains(string($0, kAXTitleAttribute)) }
        guard lists.count == 1 else { return [] }
        return (attr(lists[0], kAXChildrenAttribute) as? [AXUIElement] ?? []).compactMap { row in
            let text = string(row, kAXValueAttribute).isEmpty ? string(row, kAXTitleAttribute) : string(row, kAXValueAttribute)
            guard !text.isEmpty else { return nil }
            let desc = string(row, kAXDescriptionAttribute)
            let direction: Direction = desc.hasPrefix("发出") || desc.hasPrefix("sent") ? .outgoing :
                (desc.hasPrefix("收到") || desc.hasPrefix("received") ? .incoming : .unknown)
            return ObservedMessage(text, direction: direction, isText: !isMedia(text), deliveryFailed: desc.contains("发送失败") || desc.contains("Failed to send"))
        }
    }
    private func isMedia(_ text: String) -> Bool {
        ["[图片]", "[语音]", "[视频]", "[文件]", "[表情]", "[链接]", "[Photo]", "[Video]"].contains { text.hasPrefix($0) }
    }
    private func ocrMessages(frame: WindowFrame) -> [ObservedMessage] {
        // Use bubble placement, never infer direction from text content or default UNKNOWN to incoming.
        let left = sidebarWidth + 50, right = frame.size.width - 45
        let candidates = frame.lines.filter { $0.rect.minX > left && $0.rect.maxX < right && $0.rect.minY > 70 && $0.rect.maxY < (ocrInputRect?.minY ?? frame.size.height * 0.77) - 5 }
        let pixels = PixelMap(frame.image, size: frame.size)
        var groups: [(CGRect, String, Float)] = []
        for line in candidates {
            if line.text.range(of: "^(昨天|今天|星期.)?\\s*\\d{1,2}:\\d{2}$", options: .regularExpression) != nil { continue }
            if let last = groups.last, line.rect.minY - last.0.maxY < 9, line.rect.minY >= last.0.maxY - 3,
               abs(line.rect.minX - last.0.minX) < 10 {
                groups[groups.count - 1] = (last.0.union(line.rect), last.1 + "\n" + line.text, min(last.2, line.confidence))
            } else { groups.append((line.rect, line.text, line.confidence)) }
        }
        return groups.map { rect, text, confidence in
            let bubble = pixels?.bubbleColor(around: rect)
            let incoming = rect.minX < sidebarWidth + 125 && bubble == .incoming
            let outgoing = rect.maxX > frame.size.width - 125 && bubble == .outgoing
            let direction: Direction = confidence < 0.90 || incoming == outgoing ? .unknown : (incoming ? .incoming : .outgoing)
            let failureArea = CGRect(x: rect.minX - 38, y: rect.minY - 6, width: 32, height: rect.height + 12)
            let failed = direction == .outgoing && (pixels?.redCount(in: failureArea) ?? 0) > 2
            return ObservedMessage(text, direction: direction, isText: !isMedia(text), deliveryFailed: failed)
        }
    }
    func send(_ text: String, rule: ChatRule, valid: () -> Bool, observeBeforeTyping: (ChatSnapshot) -> Void = { _ in }, beforeSubmit: () throws -> Void) async throws -> SendReceipt {
        var frame = try await select(rule, valid: valid)
        guard valid() else { throw CancellationError() }
        let before = try await snapshot(rule: rule, frame: frame)
        observeBeforeTyping(before)
        guard valid() else { throw CancellationError() }
        try assertAvailable(frame)
        if let input = inputElement() {
            guard string(input, kAXValueAttribute).isEmpty else { throw AppFailure.message("检测到人工草稿，已停止发送") }
            AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            guard AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, text as CFString) == .success else { throw AppFailure.message("微信输入框不可写") }
        } else {
            guard let inputRect = ocrInputRect else { throw AppFailure.message("未识别输入区域") }
            let draft = frame.lines.filter { inputRect.intersects($0.rect) && !["发送(S)", "发送", "Send", "按 Enter 发送"].contains($0.text) }
            guard draft.isEmpty else { throw AppFailure.message("输入区域有文字，保留人工草稿并停止发送") }
            try click(CGPoint(x: inputRect.minX + 40, y: inputRect.minY + 20), frame: frame)
            try typeUnicode(text)
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        frame = try await capture(force: true)
        guard valid(), try title(in: frame) == rule.name, frontmost else { throw AppFailure.message("发送前状态变化；已保留输入文字，请人工检查") }
        // A final matching draft is mandatory; do not press Return into arbitrary focus.
        let actual: String
        let usingOCR: Bool
        if let input = inputElement() {
            guard (attr(input, kAXFocusedAttribute) as? Bool) == true else { throw AppFailure.message("输入框焦点改变，未发送") }
            actual = string(input, kAXValueAttribute); usingOCR = false
        } else {
            actual = frame.lines.filter { ocrInputRect?.intersects($0.rect) == true && !["发送(S)", "发送", "Send", "按 Enter 发送"].contains($0.text) }.map(\.text).joined(separator: "\n")
            usingOCR = true
        }
        guard SendVerification.matches(expected: text, observed: actual, ocr: usingOCR) else {
            throw AppFailure.message("输入内容未通过回读校验，未按发送键")
        }
        guard valid() else { throw CancellationError() }
        try assertAvailable(frame)
        try beforeSubmit()
        try key(36)
        try await Task.sleep(nanoseconds: 500_000_000)
        let after = try await snapshot(rule: rule)
        return SendReceipt(confirmed: SendVerification.hasNewLocalEcho(expected: text, before: before.messages, after: after.messages, ocr: usingOCR), snapshot: after)
    }
    private func requireActive() throws {
        try interlock.requireClear()
        try Task.checkCancellation()
        guard !suspended else { throw CancellationError() }
        guard running else {
            try interlock.trip(reason: "微信进程退出或存在多个实例，请核对账号状态")
            throw AppFailure.message("微信进程不可用，已锁定自动操作")
        }
        guard !locked, frontmost else { throw AppFailure.message("微信失去焦点或屏幕锁定，已停止操作") }
    }
    private func assertAvailable(_ frame: WindowFrame) throws {
        try requireActive()
        guard accessibility, running, !locked, frontmost else { throw AppFailure.message("微信失去焦点或权限，请重新开始托管") }
        guard frame.window.owningApplication?.processID == app?.processIdentifier else { throw AppFailure.message("微信进程已改变") }
        let root = AXUIElementCreateApplication(app!.processIdentifier)
        guard let focused = attr(root, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
              let bounds = rect(focused as! AXUIElement),
              abs(bounds.minX - frame.window.frame.minX) < 2, abs(bounds.minY - frame.window.frame.minY) < 2,
              abs(bounds.width - frame.size.width) < 2, abs(bounds.height - frame.size.height) < 2 else {
            throw AppFailure.message("当前焦点窗口与已核对的微信窗口不同，已停止操作")
        }
    }
    private func click(_ local: CGPoint, frame: WindowFrame) throws {
        try assertAvailable(frame)
        let p = CGPoint(x: frame.window.frame.minX + local.x, y: frame.window.frame.minY + local.y)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws {
        try requireActive()
        guard let pid = app?.processIdentifier else { return }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags; event?.postToPid(pid)
        }
    }
    private func typeUnicode(_ text: String) throws {
        try requireActive()
        guard let pid = app?.processIdentifier else { return }
        var chunks: [[UniChar]] = [], current: [UniChar] = []
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if current.count + units.count > 20 { chunks.append(current); current = [] }
            current.append(contentsOf: units)
        }
        if !current.isEmpty { chunks.append(current) }
        for chunk in chunks {
            var chars = chunk
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
                event?.postToPid(pid)
            }
        }
    }
}
private struct PixelMap {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    let scaleX: CGFloat
    let scaleY: CGFloat
    init?(_ image: CGImage, size: CGSize) {
        width = image.width; height = image.height
        scaleX = CGFloat(image.width) / size.width; scaleY = CGFloat(image.height) / size.height
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        pixels = data
    }
    private func rgb(_ x: CGFloat, _ y: CGFloat) -> (Int, Int, Int)? {
        let px = Int(x * scaleX), py = Int(y * scaleY)
        guard px >= 0, py >= 0, px < width, py < height else { return nil }
        let index = (py * width + px) * 4
        return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
    }
    func redCount(in rect: CGRect) -> Int {
        var count = 0
        for y in stride(from: rect.minY, to: rect.maxY, by: 2) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 2) {
                if let (r, g, b) = rgb(x, y), r > 180, r > g + 55, r > b + 45 { count += 1 }
            }
        }
        return count
    }
    func bubbleColor(around rect: CGRect) -> Direction? {
        let points = [CGPoint(x: rect.minX - 5, y: rect.midY), CGPoint(x: rect.maxX + 5, y: rect.midY),
                      CGPoint(x: rect.minX, y: rect.minY - 3), CGPoint(x: rect.maxX, y: rect.minY - 3)]
        let colors = points.compactMap { rgb($0.x, $0.y) }
        guard colors.count == 4 else { return nil }
        if colors.allSatisfy({ r, g, b in g > r + 20 && g > b + 25 }) { return .outgoing }
        if colors.allSatisfy({ r, g, b in abs(r-g) < 9 && abs(g-b) < 9 && r >= 215 && r <= 245 }) { return .incoming }
        return nil
    }
}
private extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
