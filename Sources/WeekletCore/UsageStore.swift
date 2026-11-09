import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var states: [ProviderState]
    @Published public private(set) var isRefreshing = false
    private let service: any UsageFetching
    private let clock: @Sendable () -> Date
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var lastRefresh: Date?

    public init(service: any UsageFetching = UsageService(),
                clock: @escaping @Sendable () -> Date = { Date() },
                states: [ProviderState] = Provider.allCases.map { ProviderState(provider: $0) }) {
        self.service = service
        self.clock = clock
        self.states = states
    }

    public var menuTitle: String {
        states.map { "\($0.provider.shortName) \($0.menuSummary(at: clock()))" }.joined(separator: "  |  ")
    }

    public func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refreshIfDue() {
        if lastRefresh.map({ clock().timeIntervalSince($0) >= 300 }) ?? true { refresh() }
    }

    func waitForRefresh() async { await refreshTask?.value }

    public func refresh(manual: Bool = false) {
        guard !isRefreshing else { return }
        let now = clock()
        // Manual refresh is throttled too, and never overrides a provider's Retry-After.
        if let lastRefresh, now.timeIntervalSince(lastRefresh) < 5 { return }
        let eligible = states.filter { $0.retryAt.map { $0 <= now } ?? true }.map(\.provider)
        guard !eligible.isEmpty else { return }
        lastRefresh = now
        isRefreshing = true
        for index in states.indices where eligible.contains(states[index].provider) { states[index].isLoading = true }
        let service = service
        refreshTask = Task { [weak self] in
            await withTaskGroup(of: (Provider, Result<UsageSnapshot, UsageFailure>).self) { group in
                for provider in eligible {
                    group.addTask { (provider, await service.fetch(provider, allowInteraction: manual)) }
                }
                for await (provider, result) in group {
                    guard let self, !Task.isCancelled,
                          let index = self.states.firstIndex(where: { $0.provider == provider }) else { continue }
                    self.states[index].receive(result, at: self.clock())
                }
            }
            guard let self else { return }
            for index in self.states.indices { self.states[index].isLoading = false }
            self.isRefreshing = false
            self.refreshTask = nil
        }
    }
}
