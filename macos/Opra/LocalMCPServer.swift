import Foundation
import Network
import Combine

/// Opt-in, loopback-only MCP endpoint. Conversion jobs own a separate engine so
/// requests never change the reader's selected provider or playback position.
@MainActor
final class LocalMCPServer: ObservableObject {
    static let shared = LocalMCPServer()
    static let protocolVersion = "2025-11-25"
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Stopped"
    @Published private(set) var token = ""
    @Published private(set) var port: UInt16 = 8765
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var jobs: [String: Job] = [:]
    private var settings: SettingsManager?
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Opra-MCP-\(UUID().uuidString)")
    var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

    private final class Job {
        var state = "running"
        var progress = 0.0
        var error: String?
        let url: URL
        var task: Task<Void, Never>?
        init(url: URL) { self.url = url }
        var result: [String: Any] {
            var result: [String: Any] = ["state": state, "progress": progress]
            if state == "completed" { result["filePath"] = url.path; result["resourceURI"] = "opra-audio://\(url.lastPathComponent)" }
            if let error { result["error"] = error }
            return result
        }
    }

    func start(settings: SettingsManager, port: UInt16 = 8765) {
        guard listener == nil, port > 0 else { return }
        self.settings = settings
        self.port = port
        token = UUID().uuidString + UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            status = "Starting…"
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listener === listener else { return }
                    switch state {
                    case .ready: self.isRunning = true; self.status = "Listening on \(self.endpoint)"
                    case .failed(let error): self.stop(); self.status = error.localizedDescription
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
        } catch { self.listener = nil; status = error.localizedDescription }
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        jobs.values.forEach { $0.task?.cancel() }; jobs.removeAll()
        try? FileManager.default.removeItem(at: directory)
        token = ""; isRunning = false; status = "Stopped"
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, buffer: Data())
        Task { @MainActor [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(15))
            connection?.cancel(); self?.connections.removeValue(forKey: id)
        }
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                guard buffer.count <= 1_100_000 else { self.send(connection, id: id, status: 413); return }
                if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    guard range.lowerBound < 16_384,
                          let header = String(data: buffer[..<range.lowerBound], encoding: .utf8) else {
                        self.send(connection, id: id, status: 400); return
                    }
                    let lines = header.components(separatedBy: "\r\n")
                    let request = (lines.first ?? "").split(separator: " ")
                    var headers: [String: String] = [:]
                    for line in lines.dropFirst() {
                        let parts = line.split(separator: ":", maxSplits: 1)
                        guard parts.count == 2 else { self.send(connection, id: id, status: 400); return }
                        let key = parts[0].lowercased()
                        guard headers[key] == nil else { self.send(connection, id: id, status: 400); return }
                        headers[key] = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                    guard request.count == 3, request[1] == "/mcp" else { self.send(connection, id: id, status: 404); return }
                    guard headers["host"] == "127.0.0.1:\(self.port)" || headers["host"] == "localhost:\(self.port)",
                          headers["origin"] == nil || headers["origin"] == "http://127.0.0.1:\(self.port)" || headers["origin"] == "http://localhost:\(self.port)" else {
                        self.send(connection, id: id, status: 403); return
                    }
                    guard headers["authorization"] == "Bearer \(self.token)", !self.token.isEmpty else {
                        self.send(connection, id: id, status: 401); return
                    }
                    guard request[0] == "POST" else { self.send(connection, id: id, status: 405); return }
                    guard headers["transfer-encoding"] == nil,
                          headers["content-type"]?.hasPrefix("application/json") == true,
                          let length = Int(headers["content-length"] ?? ""), (0...1_000_000).contains(length) else {
                        self.send(connection, id: id, status: 400); return
                    }
                    if let version = headers["mcp-protocol-version"], version != Self.protocolVersion && version != "2025-06-18" {
                        self.send(connection, id: id, status: 400); return
                    }
                    let body = buffer[range.upperBound...]
                    if body.count >= length {
                        let response = self.handle(Data(body.prefix(length)))
                        self.send(connection, id: id, status: response == nil ? 202 : 200, json: response)
                        return
                    }
                } else if buffer.count > 16_384 { self.send(connection, id: id, status: 431); return }
                if complete || error != nil { connection.cancel(); self.connections.removeValue(forKey: id) }
                else { self.receive(connection, id: id, buffer: buffer) }
            }
        }
    }

    private func send(_ connection: NWConnection, id: UUID, status: Int, json: [String: Any]? = nil) {
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Content Too Large", 431: "Headers Too Large"]
        var data = Data("HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task { @MainActor in self?.connections.removeValue(forKey: id) }
        })
    }

    func handle(_ data: Data) -> [String: Any]? {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return rpcError(id: NSNull(), code: -32700, message: "Parse error")
        }
        let id = message["id"] ?? NSNull()
        guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            return rpcError(id: id, code: -32600, message: "Invalid request")
        }
        if message["id"] == nil { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        var result: [String: Any]
        switch method {
        case "initialize":
            result = ["protocolVersion": Self.protocolVersion, "capabilities": ["tools": [:], "resources": [:]],
                      "serverInfo": ["name": "Opra", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"],
                      "instructions": "Start a conversion, poll audio_status, then read the returned resource URI or local file. Files expire when the server stops. OpenAI uses the app's configured API key and incurs provider charges."]
        case "ping": result = [:]
        case "tools/list": result = ["tools": Self.tools]
        case "resources/list":
            result = ["resources": jobs.values.filter { $0.state == "completed" }.map {
                ["uri": "opra-audio://\($0.url.lastPathComponent)", "name": $0.url.lastPathComponent,
                 "mimeType": $0.url.pathExtension == "wav" ? "audio/wav" : "audio/mpeg"]
            }]
        case "resources/read":
            guard let uri = params["uri"] as? String,
                  let job = jobs.values.first(where: { "opra-audio://\($0.url.lastPathComponent)" == uri && $0.state == "completed" }),
                  let size = try? job.url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 24_000_000,
                  let audio = try? Data(contentsOf: job.url) else {
                return rpcError(id: id, code: -32602, message: "Unknown resource or audio exceeds 24 MB. Use the local filePath for larger exports.")
            }
            result = ["contents": [["uri": uri, "mimeType": job.url.pathExtension == "wav" ? "audio/wav" : "audio/mpeg", "blob": audio.base64EncodedString()]]]
        case "tools/call":
            do {
                let value = try call(params["name"] as? String ?? "", arguments: params["arguments"] as? [String: Any] ?? [:])
                let text = String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
                result = ["content": [["type": "text", "text": text]], "isError": false]
            } catch {
                result = ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
            }
        default: return rpcError(id: id, code: -32601, message: "Method not found")
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func rpcError(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func call(_ name: String, arguments: [String: Any]) throws -> [String: Any] {
        if name == "audio_status" || name == "cancel_audio" {
            guard let id = arguments["jobID"] as? String, let job = jobs[id] else { throw TTSProduceError(message: "Unknown jobID.") }
            if name == "cancel_audio", job.state == "running" { job.task?.cancel(); job.state = "cancelled" }
            return job.result.merging(["jobID": id]) { a, _ in a }
        }
        guard name == "convert_text_to_audio", let settings,
              let text = arguments["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 100_000 else { throw TTSProduceError(message: "Supply text containing 1–100,000 characters to convert_text_to_audio.") }
        guard !jobs.values.contains(where: { $0.state == "running" }), jobs.count < 20 else {
            throw TTSProduceError(message: "One conversion can run at a time; at most 20 jobs per server session. Stop/start the server to clear exports.")
        }
        let engine: any AudioExportingEngine
        switch arguments["provider"] as? String ?? "kokoro" {
        case "kokoro":
            let kokoro = KokoroTTSManager()
            guard kokoro.isReady else { throw TTSProduceError(message: "Install the Kokoro model in Voices & Providers before converting.") }
            engine = kokoro
        case "ollama": engine = OllamaTTSManager()
        case "openai": engine = OpenAITTSManager()
        default: throw TTSProduceError(message: "Provider must be kokoro, ollama, or openai.")
        }
        engine.setSettingsManager(settings)
        let id = UUID().uuidString
        let job = Job(url: directory.appendingPathComponent(id).appendingPathExtension(engine.exportFileExtension))
        jobs[id] = job
        job.task = Task { @MainActor in
            do {
                try await engine.exportAudio([text], to: job.url) { job.progress = $0 }
                try Task.checkCancellation()
                job.state = "completed"
            } catch {
                job.state = Task.isCancelled ? "cancelled" : "failed"
                job.error = error.localizedDescription
                try? FileManager.default.removeItem(at: job.url)
            }
        }
        return ["jobID": id, "state": job.state]
    }

    static let tools: [[String: Any]] = [
        ["name": "convert_text_to_audio", "description": "Convert text to audio using the Mac's configured voice. Returns a jobID immediately. OpenAI is a paid cloud provider. Export speed is normal narration speed.",
         "inputSchema": ["type": "object", "properties": ["text": ["type": "string", "minLength": 1, "maxLength": 100000], "provider": ["type": "string", "enum": ["kokoro", "ollama", "openai"], "default": "kokoro"]], "required": ["text"], "additionalProperties": false]],
        ["name": "audio_status", "description": "Poll conversion progress; completed jobs include filePath and resourceURI.",
         "inputSchema": ["type": "object", "properties": ["jobID": ["type": "string"]], "required": ["jobID"], "additionalProperties": false]],
        ["name": "cancel_audio", "description": "Cancel a conversion.",
         "inputSchema": ["type": "object", "properties": ["jobID": ["type": "string"]], "required": ["jobID"], "additionalProperties": false]]
    ]
}
