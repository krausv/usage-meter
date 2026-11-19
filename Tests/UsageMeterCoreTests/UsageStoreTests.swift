import XCTest
@testable import UsageMeterCore

@MainActor
final class UsageStoreTests: XCTestCase {
    /// Counts how many times the client actually hits the network.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private func makeStore(counter: Counter, interval: TimeInterval) -> UsageStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { req in
            counter.bump()
            let json = #"{"five_hour":{"utilization":1.0,"resets_at":null},"seven_day":null,"limits":[],"spend":null}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }
        let creds = ClaudeCredentials(accessToken: "t", expiresAt: nil, subscriptionType: nil)
        let client = UsageClient(session: URLSession(configuration: config), credentialsProvider: { creds })
        return UsageStore(client: client, interval: interval)
    }

    private func waitForFirstFetch(_ store: UsageStore) async throws {
        for _ in 0..<50 where store.usage == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(store.usage)
    }

    func testRefreshIfStaleSkipsWhenFreshButRefreshesWhenStale() async throws {
        let counter = Counter()
        let store = makeStore(counter: counter, interval: 9999)

        await store.refreshNow()
        XCTAssertEqual(counter.value, 1)

        // Fresh data → skip.
        await store.refreshIfStale(9999)
        XCTAssertEqual(counter.value, 1)

        // Treat anything as stale → refresh.
        await store.refreshIfStale(0)
        XCTAssertEqual(counter.value, 2)
    }

    func testStartIsIdempotent() async throws {
        let counter = Counter()
        // Long interval so only the immediate startup fetch can happen in the test window.
        let store = makeStore(counter: counter, interval: 9999)

        store.start()
        store.start()
        store.start()
        defer { store.stop() }

        try await waitForFirstFetch(store)
        // Give any erroneous extra loops a chance to fire too.
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(counter.value, 1, "three start() calls must trigger exactly one fetch")
    }

    func testInvalidStartupIntervalDoesNotTriggerRapidPolling() async throws {
        let counter = Counter()
        let store = makeStore(counter: counter, interval: 0.001)
        store.start()
        defer { store.stop() }

        try await waitForFirstFetch(store)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(counter.value, 1)
    }

    func testInvalidIntervalChangeDoesNotTriggerRapidPolling() async throws {
        let counter = Counter()
        let store = makeStore(counter: counter, interval: 300)
        store.start()
        defer { store.stop() }

        try await waitForFirstFetch(store)
        store.setInterval(0.001)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(counter.value, 1)
    }

    func testRefreshIntervalPreferenceUsesOnlySupportedValues() {
        for interval in RefreshInterval.allCases {
            XCTAssertEqual(RefreshInterval(preferenceValue: interval.rawValue), interval)
        }

        for unsupported: TimeInterval in [0, 0.001, 120, .infinity, .nan] {
            XCTAssertEqual(RefreshInterval(preferenceValue: unsupported), .oneMinute)
        }
    }
}
