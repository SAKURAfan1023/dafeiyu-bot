import Foundation
import BotCore

/// An opt-in, loopback-only control surface for the same engine as the native panel.
@MainActor final class QQControlServer {
    private let engine: QQEngine
    private let listener: LoopbackListener
    private let token = UUID().uuidString + UUID().uuidString
    private var origin = ""
    private var clients: [UUID: LoopbackConnection] = [:]
    init(engine: QQEngine) throws {
        self.engine = engine
        listener = try LoopbackListener()
    }
    func start() {
        origin = "http://127.0.0.1:\(listener.port)"
        print("QQ_CONTROL_URL=\(origin)/#\(token)")
        print("本机控制页已就绪；尚未连接或开启自动回复")
        listener.start { [weak self] connection in
            Task { @MainActor in
                guard let self, self.clients.count < 32 else { connection.cancel(); return }
                let id = UUID(); self.clients[id] = connection
                self.receive(connection, id: id, buffer: Data())
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    self?.clients.removeValue(forKey: id)?.cancel()
                }
            }
        }
    }
    private func receive(_ connection: LoopbackConnection, id: UUID, buffer: Data) {
        connection.read { [weak self] data, ended, error in
            Task { @MainActor in
                guard let self, self.clients[id] != nil else { return }
                var buffer = buffer; if let data { buffer.append(data) }
                guard error == nil, buffer.count <= 131072 else { self.reply(connection, id: id, code: 400); return }
                guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    if ended || buffer.count > 16384 { self.reply(connection, id: id, code: 400) }
                    else { self.receive(connection, id: id, buffer: buffer) }
                    return
                }
                let lines = String(decoding: buffer[..<separator.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
                let request = (lines.first ?? "").split(separator: " ").map(String.init)
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { self.reply(connection, id: id, code: 400); return }
                    let name = line[..<colon].lowercased()
                    guard headers[name] == nil else { self.reply(connection, id: id, code: 400); return }
                    headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard request.count == 3, request[2] == "HTTP/1.1", headers["transfer-encoding"] == nil,
                      let count = Int(headers["content-length"] ?? "0"), (0...65536).contains(count),
                      headers["host"] == self.origin.replacingOccurrences(of: "http://", with: "") else {
                    self.reply(connection, id: id, code: 400); return
                }
                let body = Data(buffer[separator.upperBound...])
                if body.count < count && !ended { self.receive(connection, id: id, buffer: buffer); return }
                guard body.count == count else { self.reply(connection, id: id, code: 400); return }
                await self.handle(connection, id: id, method: request[0], path: request[1], headers: headers, body: body)
            }
        }
    }
    private func handle(_ connection: LoopbackConnection, id: UUID, method: String, path: String, headers: [String: String], body: Data) async {
        if method == "GET", ["/", "/app.js"].contains(path) {
            let name = path == "/" ? "index" : "app", ext = path == "/" ? "html" : "js"
            guard let url = RuntimeResources.directory?.appendingPathComponent("QQControl/\(name).\(ext)"),
                  let data = try? Data(contentsOf: url) else { reply(connection, id: id, code: 404); return }
            reply(connection, id: id, code: 200, data: data, type: path == "/" ? "text/html" : "text/javascript"); return
        }
        guard headers["x-qq-control"] == token,
              headers["origin"] == nil || headers["origin"] == origin else { reply(connection, id: id, code: 403); return }
        if method == "GET", path.hasPrefix("/api/sticker/") {
            let stickerID = String(path.dropFirst("/api/sticker/".count))
            guard let item = engine.stickerLibrary.items.first(where: { $0.id == stickerID }),
                  let data = engine.stickerLibrary.data(for: item) else { reply(connection, id: id, code: 404); return }
            reply(connection, id: id, code: 200, data: data, type: item.file.hasSuffix(".png") ? "image/png" : item.file.hasSuffix(".webp") ? "image/webp" : "image/jpeg"); return
        }
        if method == "POST", path == "/api/action" {
            guard headers["origin"] == origin, headers["content-type"]?.hasPrefix("application/json") == true else {
                reply(connection, id: id, code: 403); return
            }
            do {
                let request = try JSONDecoder().decode(Action.self, from: body)
                engine.error = nil
                switch request.action {
                case "addArtworkArtist":
                    guard let input = request.artistInput else { throw AppFailure.message("缺少画师主页或 ID") }
                    await engine.addArtworkArtist(input)
                case "removeArtworkArtist":
                    guard let id = request.artistInput, engine.config.effectiveArtwork.pixivArtistIDs.contains(id) else { throw AppFailure.message("画师不在列表中") }
                    var settings = engine.config.effectiveArtwork
                    settings.pixivArtistIDs.removeAll { $0 == id }; settings.artistNames?.removeValue(forKey: id)
                    settings.imagePermissions.removeValue(forKey: id); engine.saveArtwork(settings)
                case "saveArtwork":
                    guard let settings = request.artwork else { throw AppFailure.message("缺少插画设置") }
                    engine.saveArtwork(settings)
                case "saveVisualTools":
                    guard let settings = request.visualTools else { throw AppFailure.message("缺少识图设置") }
                    engine.saveVisualTools(settings, googleKey: request.googleVisionKey ?? "", persistCredentials: request.persistVisualCredentials ?? true)
                case "saveImageGeneration":
                    guard let settings = request.imageGeneration else { throw AppFailure.message("缺少生图设置") }
                    engine.saveImageGeneration(settings, zhipuKey: request.zhipuKey ?? "", cloudflareToken: request.cloudflareToken ?? "", persistCredentials: request.persistImageCredentials ?? true)
                case "pause": engine.pause()
                case "disconnect": engine.disconnect()
                case "clear": engine.clearTemporaryCredentials()
                case "takeOver":
                    guard let target = engine.config.targets.first(where: { $0.key == request.target }) else { throw AppFailure.message("会话不存在") }
                    engine.takeOver(target.id)
                case "clearMemory":
                    guard let target = engine.config.targets.first(where: { $0.key == request.target }) else { throw AppFailure.message("会话不存在") }
                    engine.clearMemory(target.id)
                case "connect":
                    guard !engine.connected, !engine.busy, !engine.runtimeBusy else { throw AppFailure.message("请先断开并等待当前操作完成") }
                    if let expected = request.expectedSelfID { engine.config.expectedSelfID = expected }
                    if let key = request.key, !key.isEmpty {
                        guard engine.useTemporaryCredentials(token: request.token ?? "", key: key) else { throw AppFailure.message(engine.error ?? "临时凭证无效") }
                    }
                    await engine.connect()
                case "add":
                    guard !engine.running, let contact = engine.contacts.first(where: { $0.id == request.target }) else { throw AppFailure.message("请暂停后从已核对联系人中选择") }
                    engine.add(contact)
                case "remove":
                    guard let target = engine.config.targets.first(where: { $0.key == request.target }) else { throw AppFailure.message("会话不存在") }
                    engine.remove(target.id)
                case "setPersona":
                    guard let target = request.target, let style = request.personaStyle else { throw AppFailure.message("缺少会话或性格") }
                    engine.setPersonaStyle(style, target: target)
                case "save":
                    guard !engine.running, !engine.busy, !engine.runtimeBusy else { throw AppFailure.message("请先暂停") }
                    var updated = engine.config
                    if let ai = request.ai { updated.ai = ai }
                    if let persona = request.persona { updated.persona = persona }
                    if let onlineEnabled = request.onlineEnabled { updated.onlineEnabled = onlineEnabled }
                    if let visionEnabled = request.visionEnabled { updated.visionEnabled = visionEnabled }
                    if let memoryEnabled = request.memoryEnabled { updated.memoryEnabled = memoryEnabled }
                    if let options = request.memoryOptions { updated.memoryOptions = options }
                    if let value = request.groupParticipationEnabled { updated.groupParticipationEnabled = value }
                    if let value = request.groupParticipationEvery { updated.groupParticipationEvery = value }
                    try updated.validate(); engine.saveReplySettings(ai: updated.ai, persona: updated.effectivePersona, onlineEnabled: updated.effectiveOnlineEnabled, visionEnabled: updated.effectiveVisionEnabled, memoryEnabled: updated.effectiveMemoryEnabled, groupParticipationEnabled: updated.effectiveGroupParticipationEnabled, groupParticipationEvery: updated.effectiveGroupParticipationEvery, memoryOptions: updated.effectiveMemoryOptions)
                case "start":
                    guard engine.connected, !engine.running, !engine.busy, !engine.runtimeBusy else { throw AppFailure.message("请先连接或暂停") }
                    let duration = request.singleReply == true ? 15 : (request.durationMinutes ?? 120)
                    guard (0...4320).contains(duration) else { throw AppFailure.message("运行时长必须为 0 至 4320 分钟") }
                    let enabled = Set(request.enabled ?? [])
                    guard enabled.isSubset(of: Set(engine.config.targets.map(\.key))) else { throw AppFailure.message("范围包含未知会话") }
                    var updated = engine.config
                    if let ai = request.ai { updated.ai = ai }
                    if let persona = request.persona { updated.persona = persona }
                    if let onlineEnabled = request.onlineEnabled { updated.onlineEnabled = onlineEnabled }
                    if let visionEnabled = request.visionEnabled { updated.visionEnabled = visionEnabled }
                    if let memoryEnabled = request.memoryEnabled { updated.memoryEnabled = memoryEnabled }
                    if let options = request.memoryOptions { updated.memoryOptions = options }
                    if let value = request.groupParticipationEnabled { updated.groupParticipationEnabled = value }
                    if let value = request.groupParticipationEvery { updated.groupParticipationEvery = value }
                    try updated.validate(); engine.config = updated
                    for index in engine.config.targets.indices { engine.config.targets[index].enabled = enabled.contains(engine.config.targets[index].key) }
                    engine.start(singleReply: request.singleReply ?? false, duration: duration == 0 ? nil : Double(duration * 60))
                default: throw AppFailure.message("不支持的操作")
                }
            } catch { engine.error = error.localizedDescription }
        } else if !(method == "GET" && path == "/api/status") { reply(connection, id: id, code: 404); return }
        do {
            let config = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.config))
            let object: [String: Any] = ["config": config, "connected": engine.connected, "running": engine.running,
                "busy": engine.busy || engine.runtimeBusy, "status": engine.status, "error": engine.error ?? "",
                "temporaryCredentials": engine.usesTemporaryCredentials,
                "supportsKeychain": RuntimeResources.supportsKeychain,
                "imageGeneration": try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.config.effectiveImageGeneration)),
                "imageCredentials": ["zhipu": engine.hasZhipuImageKey, "cloudflare": engine.hasCloudflareImageToken],
                "visualTools": try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.config.effectiveVisualTools)),
                "googleVisionCredential": engine.hasGoogleVisionKey, "visualStatus": engine.visualStatus,
                "imageGenerationStatus": engine.imageGenerationStatus,
                "artwork": try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.config.effectiveArtwork)),
                "artworkStatus": engine.artworkStatus,
                "artworkArtists": engine.config.effectiveArtwork.pixivArtistIDs.map { ["id": $0, "name": QQArtworkLibrary.artistName($0, config: engine.config.effectiveArtwork), "deliveryStatus": "公开取图，逐作检查可用性"] },
                "artworkNetworkCalls": engine.artworkLedger.networkCalls,
                "artworkConfirmed": engine.artworkLedger.deliveries.filter { $0.state == "confirmed" }.count,
                "memoryOptions": try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.config.effectiveMemoryOptions)),
                "memoryStatus": engine.memoryStatus, "memoryBusy": engine.memoryBusy,
                "memories": engine.memoryBooks.filter { $0.key.hasPrefix(engine.config.expectedSelfID + ":") }.sorted { $0.key < $1.key }.map { key, book in
                    ["key": key, "summary": book.items.filter { $0.current(Date()) }.suffix(32).map { "[\($0.subject)·\($0.kind)] \($0.text)" }.joined(separator: "\n"), "updatedAt": (book.lastCompactedAt ?? book.recent.last?.at ?? Date.distantPast).timeIntervalSince1970, "pending": book.pending.count, "items": book.items.filter { $0.current(Date()) }.count, "dropped": book.droppedEvents] as [String: Any]
                },
                "personalities": QQPersonality.allCases.map { ["id": $0.rawValue, "name": $0.name, "description": $0.description] },
                "persona": try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.config.effectivePersona)),
                "stickers": engine.stickerLibrary.items.map { ["id": $0.id, "title": $0.title, "source": $0.source, "context": $0.context ?? ""] },
                "runDeadline": engine.runDeadline.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
                "calls": engine.usage.calls, "attempts": engine.sends.attempts, "confirmed": engine.sends.confirmed,
                "groupMessageCounts": engine.groupMessageCounts,
                "queued": engine.queuedCount, "queueCapacity": QQEngine.queueCapacity,
                "uncertain": engine.sends.uncertain, "rejected": engine.rejectedScopedEvents,
                "contacts": engine.contacts.map { ["key": $0.id, "name": $0.name, "number": $0.number, "group": $0.group] as [String: Any] }]
            reply(connection, id: id, code: 200, data: try JSONSerialization.data(withJSONObject: object))
        } catch { reply(connection, id: id, code: 500) }
    }
    private struct Action: Decodable {
        var groupParticipationEnabled: Bool?
        var groupParticipationEvery: Int?
        var visualTools: QQVisualConfig?
        var googleVisionKey: String?
        var persistVisualCredentials: Bool?
        var action: String
        var artwork: QQArtworkConfig?
        var artistInput: String?
        var imageGeneration: QQImageGenerationConfig?
        var zhipuKey: String?
        var cloudflareToken: String?
        var persistImageCredentials: Bool?
        var expectedSelfID: String?
        var token: String?
        var key: String?
        var target: String?
        var enabled: [String]?
        var ai: BotConfig?
        var persona: QQPersona?
        var personaStyle: String?
        var onlineEnabled: Bool?
        var visionEnabled: Bool?
        var memoryEnabled: Bool?
        var memoryOptions: QQMemoryOptions?
        var durationMinutes: Int?
        var singleReply: Bool?
    }
    private func reply(_ connection: LoopbackConnection, id: UUID, code: Int, data: Data = Data(), type: String = "application/json") {
        let header = "HTTP/1.1 \(code) Response\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' blob:; frame-ancestors 'none'; form-action 'none'\r\n\r\n"
        connection.send(Data(header.utf8) + data) { [weak self] in
            connection.cancel()
            Task { @MainActor in self?.clients.removeValue(forKey: id) }
        }
    }
}
