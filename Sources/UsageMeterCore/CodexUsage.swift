import Foundation

/// Rate-limit snapshot z `GET chatgpt.com/backend-api/wham/usage`:
/// `{"plan_type": "plus", "rate_limit": {
/// "primary_window": {"used_percent": 1, "reset_at": 1781121633},
/// "secondary_window": {"used_percent": 28, "reset_at": 1781553834}}}`
/// `primary` je typicky 5h okno, `secondary` týdenní — ale některé plány 5h okno
/// neuvádějí vůbec, takže obě jsou optional a UI si poradí i s jedním.
/// Per-model okna (`additional_rate_limits`) záměrně ignorujeme.
public struct CodexUsage: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public let usedPercent: Double
        public let resetsAt: Date?

        public init(usedPercent: Double, resetsAt: Date?) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }
    }

    public let planType: String?
    public let primary: Window?
    public let secondary: Window?

    public init(planType: String?, primary: Window?, secondary: Window?) {
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
    }
}

public enum CodexUsageDecode {
    private struct Payload: Decodable {
        struct RateLimit: Decodable {
            let primaryWindow: RawWindow?
            let secondaryWindow: RawWindow?

            enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }
        struct RawWindow: Decodable {
            let usedPercent: Double?
            let resetAt: FlexibleEpoch?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case resetAt = "reset_at"
            }
        }
        /// `reset_at` v epoch sekundách (celé i desetinné); null/absent → nil.
        /// Dekódování je tolerantní schválně: neplatná hodnota shodí jen okno,
        /// nikdy celý snapshot.
        struct FlexibleEpoch: Decodable {
            let date: Date?
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if c.decodeNil() {
                    self.date = nil
                    return
                }
                if let epoch = try? c.decode(Double.self) {
                    self.date = Date(timeIntervalSince1970: epoch)
                    return
                }
                self.date = nil
            }
        }
        let planType: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
        }
    }

    /// Split out pro unit testy proti fixture.
    public static func decode(_ data: Data) throws -> CodexUsage {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UsageClientError.decoding(String(describing: error))
        }
        func window(_ raw: Payload.RawWindow?) -> CodexUsage.Window? {
            guard let raw, let pct = raw.usedPercent else { return nil }
            return CodexUsage.Window(usedPercent: pct, resetsAt: raw.resetAt?.date)
        }
        return CodexUsage(
            planType: payload.planType,
            primary: window(payload.rateLimit?.primaryWindow),
            secondary: window(payload.rateLimit?.secondaryWindow)
        )
    }
}
