import Foundation

/// Čte Codex subscription metr: `GET https://chatgpt.com/backend-api/wham/usage`
/// s Bearer tokenem z `~/.codex/auth.json` (případně `ChatGPT-Account-Id`).
/// Stejný endpoint, který polluje samotné CLI.
///
/// Narozdíl od Muse je to čistý status endpoint bez kvóta ceny, takže poll
/// interval může být stejný jako u Claude — 5 minut je slušnost k serveru,
/// ne nutnost. Errory schválně stejné `UsageClientError` jako ostatní
/// providery, aby `PollingStore` backoff včetně `Retry-After` fungoval všude.
public struct CodexUsageClient {
    public static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let session: URLSession
    private let credentials: () throws -> CodexAuth.Credentials

    public init(
        session: URLSession = .shared,
        credentials: @escaping () throws -> CodexAuth.Credentials = CodexAuth.readCredentials
    ) {
        self.session = session
        self.credentials = credentials
    }

    public func fetch() async throws -> CodexUsage {
        do {
            return try await attempt()
        } catch UsageClientError.unauthorized {
            // Token mohl zrotovat — soubor se čte živě, takže druhý pokus
            // automaticky bere čerstvý. Jen jednou.
            return try await attempt()
        }
    }

    private func attempt() async throws -> CodexUsage {
        let creds = try credentials()
        let request = Self.usageRequest(accessToken: creds.accessToken, accountId: creds.accountId)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageClientError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.decoding("no HTTP response")
        }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw UsageClientError.unauthorized
        case 429: throw UsageClientError.rateLimited(retryAfter: UsageClient.retryAfterSeconds(http))
        default: throw UsageClientError.http(http.statusCode)
        }

        return try CodexUsageDecode.decode(data)
    }

    /// Sestavení requestu odděleně pro testy a ladění proti živému API.
    static func usageRequest(accessToken: String, accountId: String?) -> URLRequest {
        var request = URLRequest(url: Self.usageEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

extension CodexUsageClient: SnapshotFetcher {}
