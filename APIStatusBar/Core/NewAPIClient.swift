import Foundation

enum NewAPIError: Error, Equatable {
    case httpStatus(Int)
    case apiFailure(String)
    case decoding
}

struct UserSelfResponse: Decodable, Equatable {
    let quota: Int
    let usedQuota: Int
    let requestCount: Int

    private enum CodingKeys: String, CodingKey {
        case quota
        case usedQuota = "used_quota"
        case requestCount = "request_count"
    }
}

/// One row from `/api/data/self`. new-api aggregates per (model, hour) bucket,
/// so we fold these into per-model totals on the client.
struct QuotaDataRow: Decodable, Equatable {
    let modelName: String
    let createdAt: Int64
    let count: Int
    let quota: Int
    let tokenUsed: Int

    private enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case createdAt = "created_at"
        case count
        case quota
        case tokenUsed = "token_used"
    }
}

private struct EnvelopedResponse<T: Decodable>: Decodable {
    let success: Bool
    let message: String
    let data: T?
}

struct NewAPIClient {
    let baseURL: URL
    let accessToken: String
    let session: URLSession

    init(baseURL: URL, accessToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.session = session
    }

    func getSelf() async throws -> UserSelfResponse {
        try await getEnveloped(path: "api/user/self", query: [:])
    }

    /// Fetch per-model usage rows in a time window. Server enforces a 30-day
    /// max per call — caller must split larger ranges.
    func getDataSelf(start: Date, end: Date) async throws -> [QuotaDataRow] {
        let q: [String: String] = [
            "start_timestamp": String(Int(start.timeIntervalSince1970)),
            "end_timestamp": String(Int(end.timeIntervalSince1970)),
        ]
        let rows: [QuotaDataRow]? = try await getEnveloped(path: "api/data/self", query: q)
        return rows ?? []
    }

    // MARK: - Internal

    private func getEnveloped<T: Decodable>(path: String, query: [String: String]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                        resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw NewAPIError.httpStatus(-1) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(accessToken, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NewAPIError.httpStatus(-1) }
        guard (200..<300).contains(http.statusCode) else {
            throw NewAPIError.httpStatus(http.statusCode)
        }

        let decoded: EnvelopedResponse<T>
        do {
            decoded = try JSONDecoder().decode(EnvelopedResponse<T>.self, from: data)
        } catch {
            throw NewAPIError.decoding
        }

        guard decoded.success, let payload = decoded.data else {
            throw NewAPIError.apiFailure(decoded.message)
        }
        return payload
    }
}
