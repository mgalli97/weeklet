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

private actor RotatingCredentials: CredentialReading {
    private let values: [Result<String, UsageFailure>]
    private(set) var interactions: [Bool] = []
    init(_ values: [Result<String, UsageFailure>]) { self.values = values }
    func read(for provider: Provider, allowInteraction: Bool) async throws -> Credential {
        let index = min(interactions.count, values.count - 1)
        interactions.append(allowInteraction)
        return try Credential(accessToken: values[index].get())
    }
}

private actor RotatingTransport: UsageTransport {
    private(set) var calls = 0
    private(set) var receivedNewAccess = false
    let alwaysReject: Bool
    init(alwaysReject: Bool = false) { self.alwaysReject = alwaysReject }
    func getUsage(for provider: Provider, credential: Credential) async throws -> HTTPPayload {
        calls += 1
        var request = URLRequest(url: provider.usageURL)
        credential.authorize(&request)
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" { receivedNewAccess = true }
        return HTTPPayload(status: calls == 1 || alwaysReject ? 401 : 200,
                           body: Data(#"{"seven_day":{"utilization":35}}"#.utf8))
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

    @Test func testClaudeRotationDuringUnauthorizedRequestUsesNewTokenOnce() async {
        let credentials = RotatingCredentials([.success("old-access"), .success("new-access")])
        let transport = RotatingTransport()
        let result = await UsageService(credentials: credentials, transport: transport).fetch(.claude, allowInteraction: true)
        guard case .success(let usage) = result else { return recordFailure("Expected recovery after official-tool rotation") }
        checkEqual(usage.weekly?.usedRounded, 35)
        let observed1 = await transport.calls
        checkEqual(observed1, 2)
        let observed2 = await credentials.interactions
        checkEqual(observed2, [true, false])
        let receivedNewAccess = await transport.receivedNewAccess
        checkEqual(receivedNewAccess, true)
    }

    @Test func testClaudeUnchangedRejectedTokenIsNotRetried() async {
        let credentials = RotatingCredentials([.success("same-access")])
        let transport = RotatingTransport()
        let result = await UsageService(credentials: credentials, transport: transport).fetch(.claude)
        checkEqual(result, .failure(.expiredSession))
        let observed3 = await transport.calls
        checkEqual(observed3, 1)
        let observed4 = await credentials.interactions.count
        checkEqual(observed4, 2)
    }

    @Test func testClaudeRotationRetryCannotLoop() async {
        let credentials = RotatingCredentials([.success("old-access"), .success("new-access"), .success("third-access")])
        let transport = RotatingTransport(alwaysReject: true)
        let result = await UsageService(credentials: credentials, transport: transport).fetch(.claude)
        checkEqual(result, .failure(.expiredSession))
        let observed5 = await transport.calls
        checkEqual(observed5, 2)
        let observed6 = await credentials.interactions.count
        checkEqual(observed6, 2)
    }

    @Test func testExpiredReplacementIsNeverSent() async {
        let credentials = RotatingCredentials([.success("old-access"), .failure(.expiredSession)])
        let transport = RotatingTransport()
        let result = await UsageService(credentials: credentials, transport: transport).fetch(.claude)
        checkEqual(result, .failure(.expiredSession))
        let observed7 = await transport.calls
        checkEqual(observed7, 1)
    }

    @Test func testServiceParsesSuccessfulBody() async {
        let transport = TestTransport(body: #"{"seven_day":{"utilization":61,"resets_at":null}}"#)
        let result = await UsageService(credentials: TestCredentials(), transport: transport).fetch(.claude)
        guard case .success(let usage) = result else { return recordFailure("Expected weekly usage") }
        checkEqual(usage.weekly?.remainingRounded, 39)
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
