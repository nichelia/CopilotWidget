import Foundation

enum CopilotAPIError: LocalizedError {
    case missingToken
    case invalidToken
    case unauthorized
    case notAvailable
    case rateLimited
    case keychain(String)
    case network(String)
    case invalidResponse
    case noAllowance

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "No GitHub token yet. Run `gh auth token | pbcopy`, then choose Import Token from Clipboard."
        case .invalidToken:
            "That doesn't look like a GitHub token."
        case .unauthorized:
            "GitHub rejected the token. Import a fresh one."
        case .notAvailable:
            "Copilot usage isn't available for this account."
        case .rateLimited:
            "GitHub is rate limiting requests."
        case let .keychain(message):
            message
        case let .network(message):
            message
        case .invalidResponse:
            "Unexpected response from GitHub."
        case .noAllowance:
            "GitHub returned no usage allowance for this account."
        }
    }
}

struct CopilotAPIClient {
    private let url = URL(string: "https://api.github.com/copilot_internal/user")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(token: String) async throws -> CopilotUsageData {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // GitHub rejects API requests with no User-Agent.
        request.setValue("CopilotWidget/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CopilotAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CopilotAPIError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw CopilotAPIError.unauthorized
        case 404:
            throw CopilotAPIError.notAvailable
        case 429:
            throw CopilotAPIError.rateLimited
        default:
            throw CopilotAPIError.network("GitHub returned status \(http.statusCode).")
        }

        guard let decoded = try? JSONDecoder().decode(CopilotUserResponse.self, from: data) else {
            throw CopilotAPIError.invalidResponse
        }
        return try CopilotUsageParser.parse(decoded)
    }
}
