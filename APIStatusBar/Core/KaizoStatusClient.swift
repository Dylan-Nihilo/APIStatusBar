import Foundation

/// Public, unauthenticated status feed exposed by some new-api deployments
/// (e.g. kaizo.top) at `/status/status.json`. See `kaizo-status-api-doc.md`
/// for the full schema. Refresh frequency on the backend is 5 minutes;
/// heartbeats span up to ~24h (288 entries × 5min).
struct KaizoStatusClient {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchStatus() async throws -> StatusData {
        var components = URLComponents(url: baseURL.appendingPathComponent("status/status.json"),
                                        resolvingAgainstBaseURL: false)
        // Per the doc's note 2: bust caches with a timestamp param.
        components?.queryItems = [
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
        ]
        guard let url = components?.url else { throw NewAPIError.httpStatus(-1) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw NewAPIError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let decoder = JSONDecoder()
        let payload: StatusResponse
        do {
            payload = try decoder.decode(StatusResponse.self, from: data)
        } catch {
            throw NewAPIError.decoding
        }
        guard payload.success else { throw NewAPIError.apiFailure("status feed reported success=false") }
        return payload.data
    }
}

// MARK: - Schema

struct StatusResponse: Decodable {
    let success: Bool
    let generatedAt: String
    let data: StatusData

    private enum CodingKeys: String, CodingKey {
        case success
        case generatedAt = "generated_at"
        case data
    }
}

struct StatusData: Decodable {
    let groups: [StatusGroup]
    let heartbeatList: [String: [Heartbeat]]
    /// Keys are `"{channelID}_{hours}"` — `_1`, `_6`, `_24`, `_72`.
    /// Value is `0.0…1.0` or `nil` when the window has no samples.
    let uptimeList: [String: Double?]
}

struct StatusGroup: Decodable {
    let name: String
    let monitors: [Monitor]
}

struct Monitor: Decodable {
    let id: Int
    let name: String
    let group: String
    let tag: String
    let models: String
    let baseURL: String
    let priority: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, group, tag, models, priority
        case baseURL = "base_url"
    }
}

struct Heartbeat: Decodable {
    let status: Int       // 1 = UP, 0 = DOWN
    let time: String      // "yyyy-MM-dd HH:mm:ss" UTC+8
    let ping: Int         // ms
    let msg: String
}

// MARK: - Helpers

enum KaizoStatusHelpers {
    /// Backend timestamps are Asia/Shanghai. Cache the formatter — DateFormatter
    /// allocations are expensive when iterating 288 heartbeats × N channels.
    static let beatTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parse a beat's `time` string, or nil if malformed.
    static func date(from beatTime: String) -> Date? {
        beatTimeFormatter.date(from: beatTime)
    }
}
