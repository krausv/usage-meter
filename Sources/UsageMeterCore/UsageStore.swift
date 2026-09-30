import Foundation
import Combine

/// Observable state for the UI: latest snapshot, last error, loading flag, and a
/// self-scheduling poll loop with backoff. `@MainActor` so `@Published`
/// mutations are always delivered on the main thread.
///
/// Scheduling is one-shot (not a repeating timer): after every attempt we decide
/// when to try again. On success we wait the normal `interval`; on failure we
/// back off (respecting `Retry-After` for 429s) so we never hammer a server
/// that's already pushing back. The last good `value` is kept across errors.
///
/// Generic over the snapshot type so the Claude (`Usage`) and Muse
/// (`MuseUsage`) paths share scheduling/backoff instead of duplicating it.
@MainActor
public final class PollingStore<Snapshot>: ObservableObject {
    @Published public private(set) var value: Snapshot?
    @Published public private(set) var lastError: UsageErrorKind?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastUpdated: Date?

    private let client: any SnapshotFetcher<Snapshot>
    private var interval: TimeInterval
    private var timer: Timer?
    private var consecutiveFailures = 0
    private var started = false
    private var inFlight = false

    /// Backoff ceiling — never wait longer than this between attempts, so a
    /// transient error recovers on its own within a few minutes.
    private let maxBackoff: TimeInterval = 5 * 60

    public init(client: any SnapshotFetcher<Snapshot>, interval: TimeInterval = 60) {
        self.client = client
        self.interval = interval
    }

    /// Idempotent: safe to call more than once — only the first call starts the
    /// poll loop, so we never end up with two concurrent loops double-polling.
    public func start() {
        guard !started else { return }
        started = true
        Task { await refreshNow() }
    }

    /// Change the poll cadence at runtime (from Preferences). Takes effect on the
    /// next scheduled poll; also reschedules the pending one.
    public func setInterval(_ seconds: TimeInterval) {
        guard seconds != interval else { return }
        interval = seconds
        if consecutiveFailures == 0 { scheduleNext(after: interval) }
    }

    /// Refresh only if the data is stale or currently showing an error. Used by
    /// UI triggers (menu opened, system woke) so they recover a stuck state
    /// immediately without piling on redundant requests.
    public func refreshIfStale(_ seconds: TimeInterval = 30) async {
        if lastError == nil, let last = lastUpdated, Date().timeIntervalSince(last) < seconds {
            return
        }
        await refreshNow()
    }

    /// Fetch once and (re)schedule the next poll based on the outcome.
    /// Re-entrancy-guarded so overlapping triggers can't double-fetch.
    public func refreshNow() async {
        if inFlight { return }
        inFlight = true
        defer { inFlight = false }

        isLoading = true
        var nextDelay = interval
        do {
            value = try await client.fetch()
            lastUpdated = Date()
            lastError = nil
            consecutiveFailures = 0
            nextDelay = interval
        } catch {
            consecutiveFailures += 1
            lastError = UsageErrorKind(error)
            nextDelay = backoffDelay(for: error)
        }
        isLoading = false
        scheduleNext(after: nextDelay)
    }

    /// Exponential backoff, honouring a server-provided `Retry-After` for 429s.
    private func backoffDelay(for error: Error) -> TimeInterval {
        if let retryAfter = (error as? UsageClientError)?.retryAfter {
            return min(max(TimeInterval(retryAfter), interval), maxBackoff)
        }
        let exponential = interval * pow(2, Double(consecutiveFailures - 1))
        return min(exponential, maxBackoff)
    }

    private func scheduleNext(after delay: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { _ in
            // `weak self` patří přímo na Task: slabý odkaz zachycený vnější
            // closurou by Task (concurrently-executing) nesměl číst — na to
            // si starší toolchain na CI stěžuje, novější to přejde mlčky.
            Task { @MainActor [weak self] in await self?.refreshNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }
}

/// The Claude snapshot store. A typealias so existing call sites
/// (`UsageStore(client:interval:)`, `store.usage`) keep compiling unchanged.
public typealias UsageStore = PollingStore<Usage>

extension PollingStore where Snapshot == Usage {
    /// Compatibility accessor for the Claude path; new Muse code uses `value`.
    public var usage: Usage? { value }
}
