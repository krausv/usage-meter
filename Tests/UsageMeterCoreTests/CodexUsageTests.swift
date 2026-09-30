import XCTest
@testable import UsageMeterCore

final class CodexUsageTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "codex_wham_sample", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    func testDecodesPlanAndWindows() throws {
        let usage = try CodexUsageDecode.decode(fixtureData())
        XCTAssertEqual(usage.planType, "plus")
        XCTAssertEqual(usage.primary?.usedPercent, 6)
        XCTAssertEqual(usage.secondary?.usedPercent, 28)
        XCTAssertNotNil(usage.primary?.resetsAt, "epoch reset_at must parse")
        XCTAssertEqual(
            usage.primary?.resetsAt,
            Date(timeIntervalSince1970: 1781121633),
            accuracy: 1
        )
    }

    func testToleratesMissingSecondaryWindow() throws {
        // Některé plány 5h/secondary okno neuvádějí — snapshot bez něj je validní.
        let data = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":41,"reset_at":null}}}"#.utf8)
        let usage = try CodexUsageDecode.decode(data)
        XCTAssertEqual(usage.primary?.usedPercent, 41)
        XCTAssertNil(usage.primary?.resetsAt)
        XCTAssertNil(usage.secondary)
    }

    func testIgnoresAdditionalRateLimits() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":1,"reset_at":1781},"additional_rate_limits":[{"name":"spark","primary_window":{"used_percent":99}}]}}"#.utf8)
        let usage = try CodexUsageDecode.decode(data)
        XCTAssertEqual(usage.primary?.usedPercent, 1)
    }

    func testDecodeThrowsOnGarbage() {
        XCTAssertThrowsError(try CodexUsageDecode.decode(Data("not json".utf8)))
    }

    func testAuthParsesTokenAndAccount() throws {
        let data = Data(#"{"tokens":{"access_token":"sk-abc","account_id":"acc-1"}}"#.utf8)
        let creds = try CodexAuth.parse(data)
        XCTAssertEqual(creds.accessToken, "sk-abc")
        XCTAssertEqual(creds.accountId, "acc-1")
    }

    func testAuthToleratesMissingAccountId() throws {
        let data = Data(#"{"tokens":{"access_token":"sk-abc"}}"#.utf8)
        let creds = try CodexAuth.parse(data)
        XCTAssertEqual(creds.accessToken, "sk-abc")
        XCTAssertNil(creds.accountId)
    }

    func testAuthRejectsMissingToken() {
        XCTAssertThrowsError(try CodexAuth.parse(Data(#"{"tokens":{}}"#.utf8)))
        XCTAssertThrowsError(try CodexAuth.parse(Data(#"{}"#.utf8)))
    }

    func testRequestShape() {
        let req = CodexUsageClient.usageRequest(accessToken: "tok", accountId: "acc")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acc")

        let noAccount = CodexUsageClient.usageRequest(accessToken: "tok", accountId: nil)
        XCTAssertNil(noAccount.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
    }
}
