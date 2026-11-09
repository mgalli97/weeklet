import Foundation

/// All-model weekly quotas and Claude's session quota are normalized independently.
/// Model-specific, review, credit and spend buckets never stand in for either one.
public enum ProviderContracts {
    public static func parse(_ data: Data, for provider: Provider, now: Date = Date()) throws -> UsageSnapshot {
        do {
            switch provider {
            case .claude: return try parseClaude(data, now: now)
            case .codex: return try parseCodex(data, now: now)
            }
        } catch let failure as UsageFailure {
            throw failure
        } catch {
            // Never expose decoding descriptions: a response can contain personal data.
            throw UsageFailure.invalidResponse
        }
    }

    private struct ClaudeEnvelope: Decodable {
        let seven_day: ClaudeWindow?
        let five_hour: ClaudeWindow?
        let limits: [ClaudeMeter]?
    }

    private struct ClaudeWindow: Decodable {
        let utilization: Double
        let resets_at: String?
    }

    private struct ClaudeMeter: Decodable {
        let kind: String
        let percent: Double?
        let resets_at: String?
    }

    private static func parseClaude(_ data: Data, now: Date) throws -> UsageSnapshot {
        let envelope = try JSONDecoder().decode(ClaudeEnvelope.self, from: data)
        let weekly: QuotaUsage?
        let session: QuotaUsage?
        // The server's structured meter kind is authoritative when the new array is present.
        if let meters = envelope.limits {
            weekly = try meter(meters, kind: "weekly_all", now: now)
            session = try meter(meters, kind: "session", now: now)
        } else {
            weekly = try window(envelope.seven_day, now: now)
            session = try window(envelope.five_hour, now: now)
        }
        guard weekly != nil || session != nil else { throw UsageFailure.weeklyUnavailable }
        return UsageSnapshot(weekly: weekly, session: session)
    }

    private static func meter(_ meters: [ClaudeMeter], kind: String, now: Date) throws -> QuotaUsage? {
        let matches = meters.filter { $0.kind == kind }
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1, let match = matches.first, let percent = match.percent else {
            throw UsageFailure.invalidResponse
        }
        return try QuotaUsage(usedPercent: percent, resetsAt: date(match.resets_at), fetchedAt: now)
    }

    private static func window(_ window: ClaudeWindow?, now: Date) throws -> QuotaUsage? {
        guard let window else { return nil }
        return try QuotaUsage(usedPercent: window.utilization, resetsAt: date(window.resets_at), fetchedAt: now)
    }

    private struct CodexEnvelope: Decodable { let rate_limit: CodexRateLimit? }
    private struct CodexRateLimit: Decodable {
        let primary_window: CodexWindow?
        let secondary_window: CodexWindow?
    }
    private struct CodexWindow: Decodable {
        let used_percent: Double
        let limit_window_seconds: Int
        let reset_at: Double?
    }

    private static func parseCodex(_ data: Data, now: Date) throws -> UsageSnapshot {
        let envelope = try JSONDecoder().decode(CodexEnvelope.self, from: data)
        let windows = [envelope.rate_limit?.primary_window, envelope.rate_limit?.secondary_window]
            .compactMap { $0 }.filter { $0.limit_window_seconds == 604_800 }
        guard !windows.isEmpty else { throw UsageFailure.weeklyUnavailable }
        guard windows.count == 1, let window = windows.first else { throw UsageFailure.invalidResponse }
        return UsageSnapshot(weekly: try QuotaUsage(usedPercent: window.used_percent,
                               resetsAt: window.reset_at.map { Date(timeIntervalSince1970: $0) }, fetchedAt: now))
    }

    private static func date(_ text: String?) throws -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else { throw UsageFailure.invalidResponse }
        return date
    }
}
