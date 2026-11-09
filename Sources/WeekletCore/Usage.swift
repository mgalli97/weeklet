import Foundation

public enum Provider: String, CaseIterable, Sendable, Identifiable {
    case claude, codex

    public var id: String { rawValue }
    public var name: String { self == .claude ? "Claude Code" : "Codex" }
    public var shortName: String { self == .claude ? "C" : "X" }
    public var signInHint: String {
        self == .claude ? "Sign in with Claude Code, then refresh." : "Sign in with Codex, then refresh."
    }

    public var usageURL: URL {
        switch self {
        case .claude: URL(string: "https://api.anthropic.com/api/oauth/usage")!
        case .codex: URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        }
    }
}

public struct QuotaUsage: Sendable, Equatable {
    public let usedPercent: Double
    public let resetsAt: Date?
    public let fetchedAt: Date

    public init(usedPercent: Double, resetsAt: Date?, fetchedAt: Date) throws {
        guard usedPercent.isFinite, (0...100).contains(usedPercent),
              resetsAt.map({ $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 }) ?? true
        else { throw UsageFailure.invalidResponse }
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.fetchedAt = fetchedAt
    }

    public var usedRounded: Int { Int(usedPercent.rounded()) }
    public var remainingRounded: Int { 100 - usedRounded }

    public func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) < 600 && (resetsAt.map { $0 > now } ?? true)
    }
}

/// Windows stay separate: a session quota can never replace a weekly quota.
public struct UsageSnapshot: Sendable, Equatable {
    public let weekly: QuotaUsage?
    public let session: QuotaUsage?

    public init(weekly: QuotaUsage?, session: QuotaUsage? = nil) {
        self.weekly = weekly
        self.session = session
    }
}

public enum QuotaPeriod: Sendable { case weekly, session }

public enum UsageFailure: Error, Sendable, Equatable {
    case notSignedIn
    case credentialAccess
    case insecureCredentials
    case unsupportedAuth
    case expiredSession
    case offline
    case timeout
    case rateLimited(until: Date)
    case serviceUnavailable
    case invalidResponse
    case weeklyUnavailable
    case redirectBlocked
    case cancelled

    public var message: String {
        switch self {
        case .notSignedIn: "Not signed in"
        case .credentialAccess: "Credential access unavailable"
        case .insecureCredentials: "Credential file is not private"
        case .unsupportedAuth: "Subscription sign-in required"
        case .expiredSession: "Session expired"
        case .offline: "Offline"
        case .timeout: "Request timed out"
        case .rateLimited: "Refresh limit reached"
        case .serviceUnavailable: "Provider unavailable"
        case .invalidResponse: "Usage format changed"
        case .weeklyUnavailable: "No weekly quota reported"
        case .redirectBlocked: "Unexpected redirect blocked"
        case .cancelled: "Refresh interrupted"
        }
    }

    public func detail(for provider: Provider) -> String {
        switch self {
        case .notSignedIn, .unsupportedAuth, .expiredSession: provider.signInHint
        case .credentialAccess: "Unlock Keychain, then click Refresh to allow access."
        case .insecureCredentials: "Check ownership and permissions of the provider's credential file."
        case .offline, .timeout: "Check your connection. Another refresh will run automatically."
        case .weeklyUnavailable: "This account has no available seven-day window."
        case .rateLimited: "Waiting before the next request."
        case .invalidResponse: "The provider returned an unsupported usage response."
        case .redirectBlocked: "Credentials were not forwarded to the redirect."
        case .serviceUnavailable, .cancelled: "Try refreshing again later."
        }
    }

    public var discardsPreviousUsage: Bool {
        switch self {
        case .notSignedIn, .credentialAccess, .insecureCredentials, .unsupportedAuth,
             .expiredSession, .weeklyUnavailable: true
        default: false
        }
    }
}

public struct ProviderState: Identifiable, Sendable, Equatable {
    public let provider: Provider
    public var usage: UsageSnapshot?
    public var failure: UsageFailure?
    public var isLoading: Bool
    public var lastAttempt: Date?
    public var retryAt: Date?
    public var id: Provider { provider }

    public init(provider: Provider, usage: UsageSnapshot? = nil, failure: UsageFailure? = nil) {
        self.provider = provider
        self.usage = usage
        self.failure = failure
        isLoading = false
    }

    public func menuValue(at date: Date, period: QuotaPeriod = .weekly) -> String {
        let window = period == .weekly ? usage?.weekly : usage?.session
        guard failure == nil, let window, window.isFresh(at: date) else { return "—" }
        return "\(window.remainingRounded)%"
    }

    public func menuSummary(at date: Date) -> String {
        let weekly = "\(menuValue(at: date)) w"
        return provider == .claude ? "\(menuValue(at: date, period: .session)) h · \(weekly)" : weekly
    }

    public mutating func receive(_ result: Result<UsageSnapshot, UsageFailure>, at now: Date) {
        isLoading = false
        lastAttempt = now
        switch result {
        case .success(let usage):
            self.usage = usage
            failure = nil
            retryAt = nil
        case .failure(let failure):
            self.failure = failure
            if failure.discardsPreviousUsage { usage = nil }
            if case .rateLimited(let until) = failure { retryAt = until }
            else { retryAt = nil }
        }
    }
}
