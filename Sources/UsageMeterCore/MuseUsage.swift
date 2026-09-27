import Foundation

/// Jeden rate-limit snapshot z Muse subscription metru, jak ho vrací SSE event
/// `response.subscription_usage` na konci každého streamovaného
/// `POST /v1/responses`:
/// `{"subscription":{"tier":"…","weekly":{"resets_at":…,"used_percent":0},
/// "window":{"resets_at":…,"used_percent":1,"window_duration_mins":300}}}`
/// `window_duration_mins: 300` je 5h okno — obdoba Claude 5h/weekly dvojice.
public struct MuseUsage: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public let usedPercent: Double
        public let resetsAt: Date?
        /// Délka okna v minutách (5h okno hlásí 300). Nil u weekly.
        public let durationMinutes: Int?

        public init(usedPercent: Double, resetsAt: Date?, durationMinutes: Int? = nil) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
            self.durationMinutes = durationMinutes
        }
    }

    public let tier: String?
    public let window: Window?
    public let weekly: Window?

    public init(tier: String?, window: Window?, weekly: Window?) {
        self.tier = tier
        self.window = window
        self.weekly = weekly
    }
}

/// Dekódování je tolerantní schválně: přesný tvar `resets_at` (epoch vs.
/// ISO string) není dokumentovaný, takže zkoušíme epoch-sekundy, epoch-milisekundy
/// i ISO-8601 string a při neúspěchu necháme nil místo pádu celého snapshotu.
/// Stejně tak chybějící event degraduje na nil (žádná kvóta), nikdy na chybu.
public enum MuseUsageEvent {
    private struct Payload: Decodable {
        struct Snapshot: Decodable {
            let tier: String?
            let window: RawWindow?
            let weekly: RawWindow?
        }
        struct RawWindow: Decodable {
            let usedPercent: Double?
            let resetsAt: FlexibleDate?
            let windowDurationMins: Int?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case resetsAt = "resets_at"
                case windowDurationMins = "window_duration_mins"
            }
        }
        /// `resets_at` v podobě čísla (epoch) nebo stringu (ISO-8601).
        struct FlexibleDate: Decodable {
            let date: Date?
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let epoch = try? c.decode(Double.self) {
                    // Rozlišit sekundy vs. milisekundy podle velikosti.
                    self.date = epoch > 1e12 ? Date(timeIntervalSince1970: epoch / 1000)
                                             : Date(timeIntervalSince1970: epoch)
                    return
                }
                if let raw = try? c.decode(String.self) {
                    self.date = UsageDate.parse(raw)
                    return
                }
                self.date = nil
            }
        }
        let subscription: Snapshot?
    }

    /// Vytáhne poslední `subscription` snapshot ze SSE textu. SSE nese
    /// `event: response.subscription_usage` + `data: {…}` řádky; bereme každou
    /// `data:` řádku, která se dekóduje, a vracíme poslední (finální snapshot
    /// chodí až na konci streamu). Neznámé eventy se ignorují.
    public static func parse(_ sseText: String) -> MuseUsage? {
        var last: MuseUsage?
        for line in sseText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let json = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard json.hasPrefix("{"), let data = json.data(using: .utf8) else { continue }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  let snap = payload.subscription else { continue }
            last = MuseUsage(
                tier: snap.tier,
                window: snap.window.map {
                    MuseUsage.Window(usedPercent: $0.usedPercent ?? 0,
                                     resetsAt: $0.resetsAt?.date,
                                     durationMinutes: $0.windowDurationMins)
                },
                weekly: snap.weekly.map {
                    MuseUsage.Window(usedPercent: $0.usedPercent ?? 0,
                                     resetsAt: $0.resetsAt?.date)
                }
            )
        }
        return last
    }
}
