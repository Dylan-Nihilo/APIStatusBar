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

private struct EnvelopedResponse<T: Decodable>: Decodable {
    let success: Bool
    let message: String
    let data: T?
}

struct NewAPIClient {
    let baseURL: URL
    let accessToken: String
    let userID: Int
    let session: URLSession

    init(baseURL: URL, accessToken: String, userID: Int, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.userID = userID
        self.session = session
    }

    func getSelf() async throws -> UserSelfResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/user/self"))
        req.httpMethod = "GET"
        req.setValue(accessToken, forHTTPHeaderField: "Authorization")
        req.setValue(String(userID), forHTTPHeaderField: "New-Api-User")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NewAPIError.httpStatus(-1) }
        guard (200..<300).contains(http.statusCode) else {
            throw NewAPIError.httpStatus(http.statusCode)
        }

        let decoded: EnvelopedResponse<UserSelfResponse>
        do {
            decoded = try JSONDecoder().decode(EnvelopedResponse<UserSelfResponse>.self, from: data)
        } catch {
            throw NewAPIError.decoding
        }

        guard decoded.success, let payload = decoded.data else {
            throw NewAPIError.apiFailure(decoded.message)
        }
        return payload
    }
}
