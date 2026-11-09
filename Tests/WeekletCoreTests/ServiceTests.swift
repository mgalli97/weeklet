import Foundation
import Testing
@testable import WeekletCore

private actor TestCredentials: CredentialReading {
    let failure: UsageFailure?
    init(failure: UsageFailure? = nil) { self.failure = failure }
    func read(for provider: Provider, allowInteraction: Bool) async throws -> Credential {
        if let failure { throw failure }
        return try Credential(accessToken: "synthetic-access", accountID: provider == .codex ? "synthetic-account" : nil)
    }
}

private actor TestTransport: UsageTransport {
    let payload: HTTPPayload
    let failure: URLError.Code?
    private(set) var calls = 0
    init(status: Int = 200, body: String = "{}", retryAfter: String? = nil, failure: URLError.Code? = nil) {
        payload = HTTPPayload(status: status, body: Data(body.utf8), retryAfter: retryAfter)
        self.failure = failure
    }
    func getUsage(for provider: Provider, credential: Credential) async throws -> HTTPPayload {
        calls += 1
        if let failure { throw URLError(failure) }
        return payload
    }
}

final class ServiceTests: @unchecked Sendable {
    @Test func testOnlyFixedHTTPSGETRequestsCarryCredentials() throws {
        let credential = try Credential(accessToken: "synthetic-access", accountID: "synthetic-account")
        for provider in Provider.allCases {
            let request = FixedEndpointTransport.request(for: provider, credential: credential)
            checkEqual(request.url, provider.usageURL)
            checkEqual(request.url?.scheme, "https")
            checkEqual(request.httpMethod, "GET")
            checkNil(request.httpBody)
            checkEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-access")
            checkNil(request.value(forHTTPHeaderField: "Cookie"))
            checkEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            if provider == .codex {
                checkEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "synthetic-account")
                checkNil(request.value(forHTTPHeaderField: "anthropic-beta"))
            } else {
                checkEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
                checkNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
            }
        }
    }

    @Test func testRedirectDelegateRefusesEvenSameHostRedirects() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: Provider.codex.usageURL)
        let response = HTTPURLResponse(url: Provider.codex.usageURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let request = URLRequest(url: URL(string: "https://chatgpt.com/elsewhere")!)
        RefuseRedirects().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { redirected in
            checkNil(redirected)
        }
    }

    @Test func testUnauthorizedNeverRefreshesOrRetries() async {
        let transport = TestTransport(status: 401)
        let result = await UsageService(credentials: TestCredentials(), transport: transport).fetch(.codex)
        checkEqual(result, .failure(.expiredSession))
        let count = await transport.calls
        checkEqual(count, 1)
    }

    @Test func testCredentialFailureMakesNoNetworkRequest() async {
        let transport = TestTransport()
        let result = await UsageService(credentials: TestCredentials(failure: .expiredSession), transport: transport).fetch(.claude)
        checkEqual(result, .failure(.expiredSession))
        let count = await transport.calls
        checkEqual(count, 0)
    }

    @Test func testServiceParsesSuccessfulBody() async {
        let transport = TestTransport(body: #"{"seven_day":{"utilization":61,"resets_at":null}}"#)
        let result = await UsageService(credentials: TestCredentials(), transport: transport).fetch(.claude)
        guard case .success(let usage) = result else { return recordFailure("Expected weekly usage") }
        checkEqual(usage.remainingRounded, 39)
    }

    @Test func testHTTPFailuresAreSanitized() async {
        for (status, expected) in [(302, UsageFailure.redirectBlocked), (403, .unsupportedAuth), (500, .serviceUnavailable)] {
            let transport = TestTransport(status: status, body: "personal data must never become an error")
            let result = await UsageService(credentials: TestCredentials(), transport: transport).fetch(.codex)
            checkEqual(result, .failure(expected))
        }
    }

    @Test func testTimeoutAndOfflineRemainDistinct() async {
        for (code, expected) in [(URLError.Code.timedOut, UsageFailure.timeout), (.notConnectedToInternet, .offline), (.cancelled, .cancelled)] {
            let transport = TestTransport(failure: code)
            let result = await UsageService(credentials: TestCredentials(), transport: transport).fetch(.claude)
            checkEqual(result, .failure(expected))
        }
    }

    @Test func testRetryAfterSecondsAndHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        checkEqual(UsageService.retryDate("900", now: now), now.addingTimeInterval(900))
        checkEqual(UsageService.retryDate("invalid", now: now), now.addingTimeInterval(300))
        checkEqual(UsageService.retryDate("0", now: now), now.addingTimeInterval(1))
        checkEqual(UsageService.retryDate("NaN", now: now), now.addingTimeInterval(300))
        checkEqual(UsageService.retryDate("Thu, 01 Jan 1970 01:00:00 GMT", now: now), Date(timeIntervalSince1970: 3600))
    }

    @Test func testRateLimitIsPropagatedWithBackoff() async {
        let transport = TestTransport(status: 429, retryAfter: "900")
        let before = Date()
        let result = await UsageService(credentials: TestCredentials(), transport: transport).fetch(.claude)
        guard case .failure(.rateLimited(let until)) = result else { return recordFailure("Expected rate limit") }
        checkGreaterThanOrEqual(until.timeIntervalSince(before), 899)
    }
}
