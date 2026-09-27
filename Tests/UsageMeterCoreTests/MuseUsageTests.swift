import XCTest
@testable import UsageMeterCore

final class MuseUsageTests: XCTestCase {
    private func sseFixture() throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "muse_sse_sample", withExtension: "txt", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesWindowAndWeekly() throws {
        let usage = try XCTUnwrap(MuseUsageEvent.parse(sseFixture()))
        XCTAssertEqual(usage.tier, "standard")
        XCTAssertEqual(usage.window?.usedPercent, 12)
        XCTAssertEqual(usage.window?.durationMinutes, 300)
        XCTAssertNotNil(usage.window?.resetsAt, "ISO resets_at must parse")
        XCTAssertEqual(usage.weekly?.usedPercent, 34)
        XCTAssertNotNil(usage.weekly?.resetsAt, "epoch resets_at must parse")
    }

    func testTakesLastSnapshot() {
        let text = """
        event: response.subscription_usage
        data: {"subscription":{"window":{"used_percent":1},"weekly":{"used_percent":0}}}
        event: response.subscription_usage
        data: {"subscription":{"window":{"used_percent":2},"weekly":{"used_percent":5}}}
        """
        XCTAssertEqual(MuseUsageEvent.parse(text)?.window?.usedPercent, 2)
        XCTAssertEqual(MuseUsageEvent.parse(text)?.weekly?.usedPercent, 5)
    }

    func testIgnoresUnknownEventsAndEmpty() {
        XCTAssertNil(MuseUsageEvent.parse("event: foo\ndata: {\"x\":1}\n"))
        XCTAssertNil(MuseUsageEvent.parse(""))
        // Bez subscription klíče: žádná kvóta, ne pád.
        XCTAssertNil(MuseUsageEvent.parse("data: {\"ok\":true}\n"))
    }

    func testKeychainParsesApiKey() throws {
        let data = Data(#"{"api_key": "LLM|abc", "access_token": "dca:xyz"}"#.utf8)
        XCTAssertEqual(try MuseKeychain.parse(data), "LLM|abc")
    }

    func testKeychainRejectsMissingKey() {
        XCTAssertThrowsError(try MuseKeychain.parse(Data(#"{"access_token": "dca:xyz"}"#.utf8)))
        XCTAssertThrowsError(try MuseKeychain.parse(Data(#"{"api_key": ""}"#.utf8)))
    }

    func testProbeRequestShape() {
        let req = MuseUsageClient.probeRequest(apiKey: "LLM|test")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer LLM|test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertNotNil(json["model"])
    }
}
