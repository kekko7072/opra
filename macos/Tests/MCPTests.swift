import Foundation

// Stub engines isolate protocol/HTTP tests from model downloads and paid APIs.
struct TTSProduceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
final class SettingsManager {}
@MainActor protocol AudioExportingEngine {
    var exportFileExtension: String { get }
    func setSettingsManager(_ settings: SettingsManager)
    func exportAudio(_ texts: [String], to url: URL, progress: @escaping @MainActor (Double) -> Void) async throws
}
@MainActor final class KokoroTTSManager: AudioExportingEngine {
    let isReady = true
    let exportFileExtension = "wav"
    func setSettingsManager(_ settings: SettingsManager) {}
    func exportAudio(_ texts: [String], to url: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        try await Task.sleep(for: .milliseconds(150))
        try Data("test audio".utf8).write(to: url)
        progress(1)
    }
}
typealias OllamaTTSManager = KokoroTTSManager
typealias OpenAITTSManager = KokoroTTSManager

@main struct MCPTests {
    @MainActor static func main() async throws {
        let server = LocalMCPServer()
        let port: UInt16 = 18765
        server.start(settings: SettingsManager(), port: port)
        for _ in 0..<100 {
            if server.isRunning { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(server.isRunning, server.status)
        let token = server.token
        defer { server.stop() }
        func request(_ method: String, params: [String: Any] = [:], authorized: Bool = true, origin: String? = nil) async throws -> (Int, [String: Any]) {
            var req = URLRequest(url: URL(string: server.endpoint)!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            if authorized { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            if let origin { req.setValue(origin, forHTTPHeaderField: "Origin") }
            req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
            let (data, response) = try await URLSession.shared.data(for: req)
            return ((response as! HTTPURLResponse).statusCode, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        }
        let unauthorized = try await request("initialize", authorized: false)
        precondition(unauthorized.0 == 401)
        let origin = try await request("initialize", origin: "https://untrusted.example")
        precondition(origin.0 == 403)
        let initialize = try await request("initialize", params: ["protocolVersion": LocalMCPServer.protocolVersion])
        precondition(initialize.0 == 200 && (initialize.1["result"] as? [String: Any])?["protocolVersion"] as? String == LocalMCPServer.protocolVersion)
        let tools = try await request("tools/list")
        precondition(((tools.1["result"] as? [String: Any])?["tools"] as? [Any])?.count == 3)
        let unknown = try await request("unknown")
        precondition((unknown.1["error"] as? [String: Any])?["code"] as? Int == -32601)
        let invalid = try await request("tools/call", params: ["name": "convert_text_to_audio", "arguments": ["text": " "]])
        precondition((invalid.1["result"] as? [String: Any])?["isError"] as? Bool == true)
        let conversion = try await request("tools/call", params: ["name": "convert_text_to_audio", "arguments": ["text": "Hello"]])
        let content = (conversion.1["result"] as! [String: Any])["content"] as! [[String: Any]]
        let job = try JSONSerialization.jsonObject(with: Data((content[0]["text"] as! String).utf8)) as! [String: Any]
        let id = job["jobID"] as! String
        try await Task.sleep(for: .milliseconds(250))
        let status = try await request("tools/call", params: ["name": "audio_status", "arguments": ["jobID": id]])
        let result = (status.1["result"] as! [String: Any])["content"] as! [[String: Any]]
        let completed = try JSONSerialization.jsonObject(with: Data((result[0]["text"] as! String).utf8)) as! [String: Any]
        precondition(completed["state"] as? String == "completed")
        let resource = try await request("resources/read", params: ["uri": completed["resourceURI"]!])
        precondition((resource.1["result"] as? [String: Any])?["contents"] != nil)
        let traversal = try await request("resources/read", params: ["uri": "file:///etc/passwd"])
        precondition(traversal.1["error"] != nil)
        let path = completed["filePath"] as! String
        precondition(FileManager.default.fileExists(atPath: path))
        server.stop()
        precondition(!FileManager.default.fileExists(atPath: path))
        server.start(settings: SettingsManager(), port: port)
        precondition(server.token != token)
        print("MCP tests passed: HTTP auth/origin, initialization, tools, conversion lifecycle, resource isolation, cleanup and token rotation")
    }
}
