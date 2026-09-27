import Foundation

/// Čte Muse subscription metr. Narozdíl od Claude **neexistuje REST usage
/// endpoint** (všechny `/v1/usage`, `/v1/billing`, … vracejí 404) — jediný
/// potvrzený zdroj kvóty je SSE event `response.subscription_usage` na konci
/// každého streamovaného `POST /v1/responses` (Bearer `LLM|` klíč z keychain).
///
/// Minimální strategie: jeden drobný streamovaný probe-request za poll a parse
/// posledního eventu. Chybějící event není chyba, ale `MuseUsage` s nil okny
/// ("no quota data"). Každý poll stojí drobný API traffic, proto patří Muse
/// delší interval než Claude (viz AppEnvironment).
public struct MuseUsageClient {
    public static let responsesEndpoint = URL(string: "https://api.meta.ai/v1/responses")!
    /// Lehký model pro probe — přesný request kontrakt Responses API není
    /// dokumentovaný; při 4xx je první podezřelý právě body/model.
    private static let probeModel = "muse-spark-1.3"

    private let session: URLSession
    private let apiKey: () throws -> String

    public init(
        session: URLSession = .shared,
        apiKey: @escaping () throws -> String = MuseKeychain.readApiKey
    ) {
        self.session = session
        self.apiKey = apiKey
    }

    public func fetch() async throws -> MuseUsage {
        do {
            return try await attempt()
        } catch UsageClientError.unauthorized {
            // Klíč mohl zrotovat (re-login) — klíč se čte živě z keychain,
            // takže druhý pokus automaticky bere čerstvý. Jen jednou.
            return try await attempt()
        }
    }

    private func attempt() async throws -> MuseUsage {
        let key = try apiKey()
        let request = Self.probeRequest(apiKey: key)
        let text = try await Self.streamText(session: session, request: request)
        // Schválně ne-nil: přihlášený uživatel bez eventu = "no quota data", ne error.
        return MuseUsageEvent.parse(text) ?? MuseUsage(tier: nil, window: nil, weekly: nil)
    }

    /// Sestavení probe-requestu odděleně pro testy a ladění proti živému API.
    static func probeRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: Self.responsesEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": probeModel,
            "input": "usage-meter quota probe",
            "stream": true,
        ])
        return request
    }

    /// Odstreamuje celé SSE tělo do stringu; status mapping jako `UsageClient`
    /// (schválně stejné errory, aby `PollingStore` backoff včetně `Retry-After`
    /// fungoval pro oba providery).
    static func streamText(session: URLSession, request: URLRequest) async throws -> String {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
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
        var text = ""
        do {
            for try await line in bytes.lines {
                text.append(line)
                text.append("\n")
            }
        } catch {
            throw UsageClientError.offline
        }
        return text
    }
}

extension MuseUsageClient: SnapshotFetcher {}
