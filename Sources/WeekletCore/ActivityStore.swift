import Combine
import Foundation

@MainActor
public final class ActivityStore: ObservableObject {
    @Published public private(set) var states: [ProviderActivity]
    @Published public private(set) var pulse = true
    private let reader: any ActivityReading
    private var timer: Timer?
    private var pulseTimer: Timer?
    private var task: Task<Void, Never>?

    public init(reader: any ActivityReading = LocalActivityReader(),
                states: [ProviderActivity] = Provider.allCases.map { ProviderActivity(provider: $0) }) {
        self.reader = reader
        self.states = states
    }

    public func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        pulseTimer?.invalidate()
        timer = nil
        pulseTimer = nil
        task?.cancel()
        task = nil
    }

    public func refresh() {
        guard task == nil else { return }
        task = Task { [weak self, reader] in
            let states = await reader.read()
            guard let self, !Task.isCancelled else { return }
            if self.states != states { self.states = states }
            self.updatePulseTimer()
            self.task = nil
        }
    }

    func waitForRefresh() async { await task?.value }

    func advancePulse() {
        guard pulseTimer != nil, states.contains(where: \.isWorking) else { return }
        pulse.toggle()
    }

    private func updatePulseTimer() {
        if states.contains(where: \.isWorking) {
            guard pulseTimer == nil else { return }
            let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.advancePulse() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            pulseTimer = timer
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            if !pulse { pulse = true }
        }
    }
}
