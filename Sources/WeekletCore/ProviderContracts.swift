import Foundation

/// Only the all-model weekly subscription quota is normalized. Session, model-specific,
/// review, credit and spend buckets must never stand in for a weekly quota.
public enum ProviderContracts {
    public static func parse(_ data: Data, for provider: Provider, now: Date = Date()) throws -> WeeklyUsage {
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

    private static func parseClaude(_ data: Data, now: Date) throws -> WeeklyUsage {
        let envelope = try JSONDecoder().decode(ClaudeEnvelope.self, from: data)
        // The server's structured meter kind is authoritative when the new array is present.
        if let meters = envelope.limits {
            let weekly = meters.filter { $0.kind == "weekly_all" }
            guard !weekly.isEmpty else { throw UsageFailure.weeklyUnavailable }
            guard weekly.count == 1, let meter = weekly.first, let percent = meter.percent else {
                throw UsageFailure.invalidResponse
            }
            return try WeeklyUsage(usedPercent: percent, resetsAt: date(meter.resets_at), fetchedAt: now)
        }
        guard let window = envelope.seven_day else { throw UsageFailure.weeklyUnavailable }
        return try WeeklyUsage(usedPercent: window.utilization, resetsAt: date(window.resets_at), fetchedAt: now)
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

    private static func parseCodex(_ data: Data, now: Date) throws -> WeeklyUsage {
        let envelope = try JSONDecoder().decode(CodexEnvelope.self, from: data)
        let windows = [envelope.rate_limit?.primary_window, envelope.rate_limit?.secondary_window]
            .compactMap { $0 }.filter { $0.limit_window_seconds == 604_800 }
        guard !windows.isEmpty else { throw UsageFailure.weeklyUnavailable }
        guard windows.count == 1, let window = windows.first else { throw UsageFailure.invalidResponse }
        return try WeeklyUsage(usedPercent: window.used_percent,
                               resetsAt: window.reset_at.map { Date(timeIntervalSince1970: $0) }, fetchedAt: now)
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
