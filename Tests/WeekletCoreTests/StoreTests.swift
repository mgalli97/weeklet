import Foundation
import Testing
@testable import WeekletCore

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_790_000_000)
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

private actor TestService: UsageFetching {
    private(set) var calls: [Provider] = []
    private(set) var interactions: [Bool] = []
    let clock: TestClock
    let claudeFailure: UsageFailure?
    init(clock: TestClock, claudeFailure: UsageFailure? = nil) { self.clock = clock; self.claudeFailure = claudeFailure }
    func fetch(_ provider: Provider, allowInteraction: Bool) async -> Result<UsageSnapshot, UsageFailure> {
        calls.append(provider)
        interactions.append(allowInteraction)
        if provider == .claude, let claudeFailure { return .failure(claudeFailure) }
        return .success(UsageSnapshot(weekly: try! QuotaUsage(usedPercent: 25, resetsAt: clock.now().addingTimeInterval(3600), fetchedAt: clock.now())))
    }
}

final class StoreTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func testOldUsageIsNeverPresentedAsCurrentInMenuBar() throws {
        let usage = try QuotaUsage(usedPercent: 25, resetsAt: now.addingTimeInterval(3600), fetchedAt: now)
        var state = ProviderState(provider: .claude, usage: UsageSnapshot(weekly: usage))
        checkEqual(state.menuValue(at: now), "75%")
        checkEqual(state.menuValue(at: now.addingTimeInterval(601)), "—")
        state.receive(.failure(.offline), at: now)
        checkEqual(state.menuValue(at: now), "—")
        checkNotNil(state.usage)
    }

    @Test func testPastResetInvalidatesEvenRecentlyFetchedUsage() throws {
        let usage = try QuotaUsage(usedPercent: 25, resetsAt: now.addingTimeInterval(30), fetchedAt: now)
        checkFalse(usage.isFresh(at: now.addingTimeInterval(31)))
    }

    @Test func testSignOutClearsPreviousAccountUsage() throws {
        let usage = try QuotaUsage(usedPercent: 25, resetsAt: nil, fetchedAt: now)
        for failure in [UsageFailure.expiredSession, .notSignedIn, .credentialAccess, .unsupportedAuth, .weeklyUnavailable] {
            var state = ProviderState(provider: .codex, usage: UsageSnapshot(weekly: usage))
            state.receive(.failure(failure), at: now)
            checkNil(state.usage)
        }
    }

    @Test @MainActor func testRefreshCoalescesAndThrottlesManualClicks() async {
        let clock = TestClock()
        let service = TestService(clock: clock)
        let store = UsageStore(service: service, clock: { clock.now() })
        store.refresh(manual: true)
        store.refresh(manual: true)
        await store.waitForRefresh()
        var calls = await service.calls
        checkEqual(calls.count, 2)
        checkEqual(store.menuTitle, "C — h · 75% w  |  X 75% w")
        store.refresh(manual: true)
        await store.waitForRefresh()
        calls = await service.calls
        checkEqual(calls.count, 2)
        clock.advance(6)
        store.refresh()
        await store.waitForRefresh()
        calls = await service.calls
        checkEqual(calls.count, 4)
        let interactions = await service.interactions
        checkEqual(interactions.filter { $0 }.count, 2)
    }

    @Test @MainActor func testOneProviderFailureDoesNotBlockTheOther() async {
        let clock = TestClock()
        let service = TestService(clock: clock, claudeFailure: .expiredSession)
        let store = UsageStore(service: service, clock: { clock.now() })
        store.refresh()
        await store.waitForRefresh()
        checkEqual(store.states[0].failure, .expiredSession)
        checkNotNil(store.states[1].usage)
        checkEqual(store.menuTitle, "C — h · — w  |  X 75% w")
    }

    @Test @MainActor func testManualRefreshRespectsProviderBackoff() async {
        let clock = TestClock()
        let service = TestService(clock: clock, claudeFailure: .rateLimited(until: clock.now().addingTimeInterval(900)))
        let store = UsageStore(service: service, clock: { clock.now() })
        store.refresh()
        await store.waitForRefresh()
        clock.advance(300)
        store.refresh(manual: true)
        await store.waitForRefresh()
        let calls = await service.calls
        checkEqual(calls.filter { $0 == .claude }.count, 1)
        checkEqual(calls.filter { $0 == .codex }.count, 2)
    }

    @Test @MainActor func testWakeRefreshOnlyRunsWhenDue() async {
        let clock = TestClock()
        let service = TestService(clock: clock)
        let store = UsageStore(service: service, clock: { clock.now() })
        store.refreshIfDue()
        await store.waitForRefresh()
        clock.advance(299)
        store.refreshIfDue()
        await store.waitForRefresh()
        var calls = await service.calls
        checkEqual(calls.count, 2)
        clock.advance(1)
        store.refreshIfDue()
        await store.waitForRefresh()
        calls = await service.calls
        checkEqual(calls.count, 4)
    }

    @Test func testSessionResetDoesNotInvalidateTheWeeklyMenuValue() throws {
        let weekly = try QuotaUsage(usedPercent: 5, resetsAt: now.addingTimeInterval(3600), fetchedAt: now)
        let session = try QuotaUsage(usedPercent: 42, resetsAt: now.addingTimeInterval(30), fetchedAt: now)
        let state = ProviderState(provider: .claude, usage: UsageSnapshot(weekly: weekly, session: session))
        checkEqual(state.menuValue(at: now.addingTimeInterval(31)), "95%")
        checkFalse(session.isFresh(at: now.addingTimeInterval(31)))
    }

    @Test func testMenuSummaryLabelsEachAvailableQuota() throws {
        let weekly = try QuotaUsage(usedPercent: 30, resetsAt: nil, fetchedAt: now)
        let session = try QuotaUsage(usedPercent: 40, resetsAt: nil, fetchedAt: now)
        let usage = UsageSnapshot(weekly: weekly, session: session)
        checkEqual(ProviderState(provider: .claude, usage: usage).menuSummary(at: now), "60% h · 70% w")
        checkEqual(ProviderState(provider: .codex, usage: usage).menuSummary(at: now), "70% w")
    }

    @Test func testExpiredSessionMenuValueDoesNotHideFreshWeeklyValue() throws {
        let weekly = try QuotaUsage(usedPercent: 30, resetsAt: nil, fetchedAt: now)
        let session = try QuotaUsage(usedPercent: 40, resetsAt: now.addingTimeInterval(30), fetchedAt: now)
        let state = ProviderState(provider: .claude, usage: UsageSnapshot(weekly: weekly, session: session))
        checkEqual(state.menuSummary(at: now.addingTimeInterval(31)), "— h · 70% w")
    }
}
