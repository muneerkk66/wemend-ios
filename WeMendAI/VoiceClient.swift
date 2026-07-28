import Foundation

/// Talks to the WeMendAI FastAPI backend.
///
/// Turn-based by design: record a full utterance, upload, wait, play the reply.
/// The backend cannot stream audio faster than realtime when using CSM (measured
/// 0.43x on an RTX 4090), so there is nothing to be gained from a socket here.
/// See the backend's docs/LATENCY.md.
struct TurnResult: Decodable {
    let heard: String
    let replyText: String
    let audioURL: String
    let audioSeconds: Double
    let tts: TTSStats
    let timingMs: Timing

    struct TTSStats: Decodable {
        let engine: String
        let genMs: Int
        let realtimeFactor: Double
        enum CodingKeys: String, CodingKey {
            case engine
            case genMs = "gen_ms"
            case realtimeFactor = "realtime_factor"
        }
    }

    struct Timing: Decodable {
        let stt: Int
        let llm: Int
        let tts: Int
        let total: Int
    }

    enum CodingKeys: String, CodingKey {
        case heard
        case replyText = "reply_text"
        case audioURL = "audio_url"
        case audioSeconds = "audio_seconds"
        case tts
        case timingMs = "timing_ms"
    }
}

struct Health: Decodable {
    let ready: Bool
    let llm: String
    let ttsEngines: [String]
    enum CodingKeys: String, CodingKey {
        case ready, llm
        case ttsEngines = "tts_engines"
    }
}

enum ClientError: LocalizedError {
    case badStatus(Int, String)
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Server is still loading models. CSM takes ~45s, Whisper ~2min."
        case let .badStatus(code, body):
            return "Server returned \(code): \(body)"
        }
    }
}

actor VoiceClient {
    private let baseURL: URL
    private var sessionID: String?
    private let urlSession: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.default
        // CSM can take ~25s to synthesize a 10s reply — the default 60s timeout
        // is not enough once model load or a long reply is involved.
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 600
        self.urlSession = URLSession(configuration: cfg)
    }

    func health() async throws -> Health {
        let (data, resp) = try await urlSession.data(from: baseURL.appending(path: "health"))
        try Self.check(resp, data)
        return try JSONDecoder().decode(Health.self, from: data)
    }

    /// Creates a session once and reuses it so the mediator keeps conversational context.
    func ensureSession(speaker: String, listener: String) async throws -> String {
        if let sessionID { return sessionID }
        var req = URLRequest(url: baseURL.appending(path: "session"))
        req.httpMethod = "POST"
        let body = MultipartBody()
        body.addField("speaker", speaker)
        body.addField("listener", listener)
        req.setValue(body.contentType, forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await urlSession.upload(for: req, from: body.finalize())
        try Self.check(resp, data)
        struct R: Decodable { let session_id: String }
        let id = try JSONDecoder().decode(R.self, from: data).session_id
        sessionID = id
        return id
    }

    /// Voice is fixed to Sesame CSM server-side (TTS_ENGINE=csm), so no engine
    /// parameter is sent. Expect this call to take a while: CSM runs ~0.43x
    /// realtime, so a 10s reply needs ~25s.
    func send(audio fileURL: URL,
              speaker: String, listener: String) async throws -> (TurnResult, Data) {
        let sid = try await ensureSession(speaker: speaker, listener: listener)

        var req = URLRequest(url: baseURL.appending(path: "turn"))
        req.httpMethod = "POST"
        let body = MultipartBody()
        body.addField("session_id", sid)
        body.addFile("audio", filename: fileURL.lastPathComponent,
                     mimeType: "audio/m4a", data: try Data(contentsOf: fileURL))
        req.setValue(body.contentType, forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await urlSession.upload(for: req, from: body.finalize())
        try Self.check(resp, data)
        let result = try JSONDecoder().decode(TurnResult.self, from: data)

        // Fetch the reply audio (relative path returned by the API).
        let audioURL = baseURL.appending(path: String(result.audioURL.dropFirst()))
        let (audioData, audioResp) = try await urlSession.data(from: audioURL)
        try Self.check(audioResp, audioData)
        return (result, audioData)
    }

    /// Reset conversational context (new call).
    func endSession() { sessionID = nil }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 503 { throw ClientError.notReady }
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw ClientError.badStatus(http.statusCode, body)
        }
    }
}

/// Minimal multipart/form-data builder — avoids pulling in a dependency.
final class MultipartBody {
    private let boundary = "wemend.\(UUID().uuidString)"
    private var data = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    func addField(_ name: String, _ value: String) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append("\(value)\r\n")
    }

    func addFile(_ name: String, filename: String, mimeType: String, data fileData: Data) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        data.append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        data.append("\r\n")
    }

    func finalize() -> Data {
        var out = data
        out.append("--\(boundary)--\r\n")
        return out
    }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }
}
