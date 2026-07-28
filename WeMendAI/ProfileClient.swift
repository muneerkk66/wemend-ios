import Foundation

/// Profile + consent calls. Separate from `VoiceClient` for the same reason the
/// backend splits the routers: these must work while the GPU pod is stopped, and
/// keeping them apart makes that constraint visible rather than incidental.
actor ProfileClient {
    private let baseURL: URL
    private let bearer: String
    private let session: URLSession

    init(baseURL: URL, bearer: String) {
        self.baseURL = baseURL
        self.bearer = bearer
        let cfg = URLSessionConfiguration.default
        // Short, unlike VoiceClient's 300s: no model inference happens here, so a
        // slow response means something is wrong rather than merely busy.
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    private func request(_ path: String, method: String, body: Any? = nil) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw ClientError.signedOut }
            throw ClientError.badStatus(http.statusCode,
                                        String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
    }

    func get() async throws -> ProfileOut {
        let (data, resp) = try await session.data(for: try request("profile", method: "GET"))
        try check(resp, data)
        return try JSONDecoder().decode(ProfileOut.self, from: data)
    }

    /// Sends only the fields being changed — the server patches, it does not replace,
    /// so an omitted field keeps its value.
    @discardableResult
    func patch(_ fields: [String: Any]) async throws -> ProfileOut {
        let (data, resp) = try await session.data(
            for: try request("profile", method: "PATCH", body: fields))
        try check(resp, data)
        return try JSONDecoder().decode(ProfileOut.self, from: data)
    }

    func setConsent(kind: String, granted: Bool) async throws {
        let (data, resp) = try await session.data(
            for: try request("profile/consents", method: "POST",
                             body: ["kind": kind, "granted": granted]))
        try check(resp, data)
    }
}

struct ProfileOut: Decodable {
    let displayName: String?
    let pronouns: String
    let relationshipStatus: String
    let togetherMonths: Int?
    let pacingPreference: String
    let goalText: String?
    let onboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case pronouns
        case relationshipStatus = "relationship_status"
        case togetherMonths = "together_months"
        case pacingPreference = "pacing_preference"
        case goalText = "goal_text"
        case onboardingComplete = "onboarding_complete"
    }
}
