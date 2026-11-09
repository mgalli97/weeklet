import Foundation
import Testing
@testable import WeekletCore

final class ContractTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func parse(_ text: String, _ provider: Provider) throws -> QuotaUsage {
        guard let weekly = try ProviderContracts.parse(Data(text.utf8), for: provider, now: now).weekly else {
            throw UsageFailure.weeklyUnavailable
        }
        return weekly
    }
    private func expectFailure(_ text: String, _ provider: Provider, _ expected: UsageFailure) {
        checkThrowsError(try parse(text, provider)) { checkEqual($0 as? UsageFailure, expected) }
    }

    @Test func testClaudeLegacyPercentIsNotAFraction() throws {
        let value = try parse(#"{"seven_day":{"utilization":0.75,"resets_at":"2026-11-12T08:00:00Z"}}"#, .claude)
        checkEqual(value.usedPercent, 0.75)
        checkEqual(value.fetchedAt, now)
        checkEqual(value.remainingRounded, 99)
    }

    @Test func testClaudeFractionalISODate() throws {
        let value = try parse(#"{"seven_day":{"utilization":43.2,"resets_at":"2026-11-12T08:00:00.123456+00:00"}}"#, .claude)
        checkEqual(value.usedPercent, 43.2)
        checkNotNil(value.resetsAt)
    }

    @Test func testClaudeStructuredMetersSelectAllModels() throws {
        let value = try parse(#"{"limits":[{"kind":"session","percent":90},{"kind":"weekly_scoped","percent":98},{"kind":"weekly_all","percent":37,"resets_at":"2026-11-12T08:00:00Z"}]}"#, .claude)
        checkEqual(value.usedPercent, 37)
    }

    @Test func testClaudeDoesNotSubstituteScopedOrStaleLegacyWindow() {
        expectFailure(#"{"seven_day":{"utilization":20},"limits":[{"kind":"weekly_scoped","percent":98}]}"#, .claude, .weeklyUnavailable)
    }

    @Test func testClaudeNullAndMissingWeekAreUnavailable() {
        expectFailure(#"{"seven_day":null,"five_hour":{"utilization":10}}"#, .claude, .weeklyUnavailable)
        expectFailure(#"{"limits":[]}"#, .claude, .weeklyUnavailable)
    }

    @Test func testClaudeAmbiguousMetersFail() {
        expectFailure(#"{"limits":[{"kind":"weekly_all","percent":10},{"kind":"weekly_all","percent":20}]}"#, .claude, .invalidResponse)
    }

    @Test func testClaudeInvalidResetFailsWithoutInventingDate() {
        expectFailure(#"{"seven_day":{"utilization":20,"resets_at":"tomorrow"}}"#, .claude, .invalidResponse)
    }

    @Test func testCodexWeeklyCanBePrimary() throws {
        let value = try parse(#"{"rate_limit":{"primary_window":{"used_percent":67,"limit_window_seconds":604800,"reset_at":1794500000},"secondary_window":null},"credits":{"balance":"500"}}"#, .codex)
        checkEqual(value.usedPercent, 67)
        checkEqual(value.resetsAt, Date(timeIntervalSince1970: 1_794_500_000))
    }

    @Test func testCodexWeeklyCanBeSecondary() throws {
        let value = try parse(#"{"rate_limit":{"primary_window":{"used_percent":90,"limit_window_seconds":18000},"secondary_window":{"used_percent":26,"limit_window_seconds":604800,"reset_at":1794500000}}}"#, .codex)
        checkEqual(value.usedPercent, 26)
    }

    @Test func testCodexNeverSubstitutesDailyOrReviewQuota() {
        expectFailure(#"{"rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":86400}},"code_review_rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":604800}}}"#, .codex, .weeklyUnavailable)
    }

    @Test func testCodexAmbiguousWeekFails() {
        expectFailure(#"{"rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":604800},"secondary_window":{"used_percent":20,"limit_window_seconds":604800}}}"#, .codex, .invalidResponse)
    }

    @Test func testUnknownResetIsExplicitlyOptional() throws {
        let value = try parse(#"{"seven_day":{"utilization":0,"resets_at":null}}"#, .claude)
        checkNil(value.resetsAt)
        checkEqual(value.remainingRounded, 100)
    }

    @Test func testMalformedAndOutOfRangeValuesFail() {
        for text in ["not json", #"{"seven_day":{"utilization":"60"}}"#, #"{"seven_day":{"utilization":-1}}"#, #"{"seven_day":{"utilization":101}}"#] {
            expectFailure(text, .claude, .invalidResponse)
        }
        checkThrowsError(try QuotaUsage(usedPercent: .nan, resetsAt: nil, fetchedAt: now))
        checkThrowsError(try QuotaUsage(usedPercent: .infinity, resetsAt: nil, fetchedAt: now))
    }

    @Test func testRoundingKeepsTotalsAtOneHundred() throws {
        for percent in [0.0, 0.5, 23.5, 99.5, 100] {
            let value = try QuotaUsage(usedPercent: percent, resetsAt: nil, fetchedAt: now)
            checkEqual(value.usedRounded + value.remainingRounded, 100)
        }
    }

    @Test func testClaudeLegacySessionStaysSeparateFromWeek() throws {
        let data = Data(#"{"seven_day":{"utilization":5,"resets_at":"2026-11-16T13:00:00Z"},"five_hour":{"utilization":42,"resets_at":"2026-11-09T20:00:00Z"}}"#.utf8)
        let value = try ProviderContracts.parse(data, for: .claude, now: now)
        checkEqual(value.weekly?.usedPercent, 5)
        checkEqual(value.session?.usedPercent, 42)
        checkEqual(value.session?.remainingRounded, 58)
        checkEqual(value.session?.resetsAt, ISO8601DateFormatter().date(from: "2026-11-09T20:00:00Z"))
    }

    @Test func testClaudeStructuredSessionIsSelectedByKind() throws {
        let data = Data(#"{"limits":[{"kind":"weekly_scoped","percent":99},{"kind":"weekly_all","percent":5},{"kind":"session","percent":42,"resets_at":"2026-11-09T20:00:00Z"}]}"#.utf8)
        let value = try ProviderContracts.parse(data, for: .claude, now: now)
        checkEqual(value.weekly?.usedPercent, 5)
        checkEqual(value.session?.usedPercent, 42)
    }

    @Test func testSessionOnlyResponseNeverBecomesAWeeklyPercentage() throws {
        let data = Data(#"{"seven_day":null,"five_hour":{"utilization":42}}"#.utf8)
        let value = try ProviderContracts.parse(data, for: .claude, now: now)
        checkNil(value.weekly)
        checkEqual(value.session?.usedPercent, 42)
        checkEqual(ProviderState(provider: .claude, usage: value).menuValue(at: now), "—")
    }

    @Test func testAbsentSessionIsUnknownRatherThanZero() throws {
        for text in [#"{"seven_day":{"utilization":5},"five_hour":null}"#,
                     #"{"limits":[{"kind":"weekly_all","percent":5}]}"#] {
            let value = try ProviderContracts.parse(Data(text.utf8), for: .claude, now: now)
            checkEqual(value.weekly?.usedPercent, 5)
            checkNil(value.session)
        }
    }

    @Test func testAmbiguousOrInvalidSessionFailsClosed() {
        for text in [#"{"limits":[{"kind":"weekly_all","percent":5},{"kind":"session","percent":10},{"kind":"session","percent":20}]}"#,
                     #"{"seven_day":{"utilization":5},"five_hour":{"utilization":101}}"#] {
            checkThrowsError(try ProviderContracts.parse(Data(text.utf8), for: .claude, now: now)) {
                checkEqual($0 as? UsageFailure, .invalidResponse)
            }
        }
    }
}
