import Foundation

/// A peer control surface; its token, engine, jobs and browser belong only to Xiaohongshu.
@MainActor final class SocialControlServer {
    private let engine: SocialEngine
    private let listener: LoopbackListener
    private let token = UUID().uuidString + UUID().uuidString
    private var clients: [UUID: LoopbackConnection] = [:]
    private var jobs: [String: [String: String]] = [:]
    private var jobHashes: [String: String] = [:]
    private var running = false
    private var origin: String { "http://127.0.0.1:\(listener.port)" }
    var controlURL: URL { URL(string: origin + "/#" + token)! }
    init(engine: SocialEngine) throws { self.engine = engine; listener = try LoopbackListener() }
    func start(announce: Bool = false) {
        guard !running else { return }; running = true
        if announce { print("XHS_CONTROL_URL=\(controlURL.absoluteString)") }
        listener.start { [weak self] connection in
            Task { @MainActor in
                guard let self, self.running else { connection.cancel(); return }
                let id = UUID(); self.clients[id] = connection; self.receive(connection, id: id, buffer: Data())
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000); self?.clients.removeValue(forKey: id)?.cancel()
                }
            }
        }
    }
    func stop() { running = false; listener.stop(); clients.values.forEach { $0.cancel() }; clients = [:] }
    private func receive(_ connection: LoopbackConnection, id: UUID, buffer: Data) {
        connection.read { [weak self] data, ended, failure in
            Task { @MainActor in
                guard let self, self.running, self.clients[id] != nil else { return }
                var buffer = buffer; buffer.append(data ?? Data())
                guard failure == nil, buffer.count <= 65536 else { self.reply(connection, id: id, code: 400); return }
                guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    if !ended { self.receive(connection, id: id, buffer: buffer) } else { self.reply(connection, id: id, code: 400) }; return
                }
                guard range.lowerBound <= 8192, let header = String(data: buffer[..<range.lowerBound], encoding: .utf8) else { self.reply(connection, id: id, code: 400); return }
                let lines = header.components(separatedBy: "\r\n"), first = lines[0].components(separatedBy: " ")
                var fields: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { self.reply(connection, id: id, code: 400); return }
                    let key = line[..<colon].lowercased()
                    guard fields[key] == nil else { self.reply(connection, id: id, code: 400); return }
                    fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard first.count == 3, first[2] == "HTTP/1.1", fields["host"] == String(self.origin.dropFirst(7)),
                      fields["transfer-encoding"] == nil, let length = Int(fields["content-length"] ?? "0"), (0...32768).contains(length) else { self.reply(connection, id: id, code: 400); return }
                let body = Data(buffer[range.upperBound...])
                if body.count < length && !ended { self.receive(connection, id: id, buffer: buffer); return }
                guard body.count == length else { self.reply(connection, id: id, code: 400); return }
                self.handle(connection, id: id, method: first[0], path: first[1], fields: fields, body: body)
            }
        }
    }
    private func handle(_ connection: LoopbackConnection, id: UUID, method: String, path: String, fields: [String: String], body: Data) {
        let assets = ["/":"index.html", "/app.js":"app.js", "/style.css":"style.css"]
        let assetPath = String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        if method == "GET", let asset = assets[assetPath] {
            let roots = [RuntimeResources.directory, URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")].compactMap { $0 }
            guard let file = roots.map({ $0.appendingPathComponent("SocialControl/" + asset) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }), let bytes = try? Data(contentsOf: file) else { reply(connection, id: id, code: 404); return }
            let type = asset.hasSuffix(".html") ? "text/html" : asset.hasSuffix(".js") ? "text/javascript" : "text/css"
            reply(connection, id: id, code: 200, data: bytes, type: type); return
        }
        guard fields["x-social-control"] == token, fields["origin"] == nil || fields["origin"] == origin else { reply(connection, id: id, code: 403); return }
        if method == "GET", path == "/api/status" { json(connection, id: id, object: engine.snapshot); return }
        if method == "GET", path.hasPrefix("/api/job/") {
            let key = UUID(uuidString: String(path.dropFirst(9)))?.uuidString ?? ""
            json(connection, id: id, object: jobs[key] ?? ["state":"unknown"]); return
        }
        guard method == "POST", path == "/api/action", fields["origin"] == origin,
              fields["content-type"]?.hasPrefix("application/json") == true,
              let command = try? JSONDecoder().decode(SocialCommand.self, from: body) else { reply(connection, id: id, code: 400); return }
        let key = command.requestID.uuidString
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let hash = socialHash(String(decoding: (try? encoder.encode(command)) ?? Data(), as: UTF8.self))
        if let old = jobHashes[key] {
            guard old == hash else { reply(connection, id: id, code: 409); return }
        } else {
            if jobs.count >= 200 {
                for key in jobs.keys.filter({ jobs[$0]?["state"] != "pending" }).prefix(100) { jobs.removeValue(forKey: key); jobHashes.removeValue(forKey: key) }
            }
            guard jobs.count < 200 else { reply(connection, id: id, code: 429); return }
            jobs[key] = ["state":"pending"]; jobHashes[key] = hash
            Task { [weak self] in
                guard let self else { return }
                do { try await engine.perform(command); jobs[key] = ["state":"complete"] }
                catch { jobs[key] = ["state":"failed", "error": error.localizedDescription] }
            }
        }
        json(connection, id: id, code: 202, object: ["requestID": key, "state": jobs[key]?["state"] ?? "pending"])
    }
    private func json(_ connection: LoopbackConnection, id: UUID, code: Int = 200, object: [String: Any]) {
        reply(connection, id: id, code: code, data: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data())
    }
    private func reply(_ connection: LoopbackConnection, id: UUID, code: Int, data: Data = Data(), type: String = "application/json") {
        let header = "HTTP/1.1 \(code) Response\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; form-action 'none'\r\n\r\n"
        connection.send(Data(header.utf8) + data) { [weak self] in connection.cancel(); Task { @MainActor in self?.clients.removeValue(forKey: id) } }
    }
}
