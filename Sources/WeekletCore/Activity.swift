import Foundation

public enum ActivityVerb: String, CaseIterable, Sendable {
    case thinking, brewing, cooking, crafting, pondering, baking

    public var compact: String {
        switch self {
        case .thinking: "think…"
        case .brewing: "brew…"
        case .cooking: "cook…"
        case .crafting: "craft…"
        case .pondering: "pond…"
        case .baking: "bake…"
        }
    }

    public var next: ActivityVerb {
        let values = Self.allCases
        return values[(values.firstIndex(of: self)! + 1) % values.count]
    }
}

public struct WorkingChat: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?

    public init(id: String, title: String?) {
        self.id = id
        self.title = Self.sanitizedTitle(title)
    }

    static func sanitizedTitle(_ title: String?) -> String? {
        let safe = title.map { String($0.prefix(512).unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()) }
        let cleaned = safe?.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return cleaned.flatMap { $0.isEmpty ? nil : String($0.prefix(160)) }
    }
}

public struct ProviderActivity: Sendable, Equatable {
    public let provider: Provider
    public let chats: [WorkingChat]
    public var activeCount: Int { chats.count }
    public var isWorking: Bool { !chats.isEmpty }
    public var title: String? { chats.first?.title }

    public init(provider: Provider, isWorking: Bool = false, title: String? = nil) {
        self.provider = provider
        chats = isWorking ? [WorkingChat(id: "active", title: title)] : []
    }

    public init(provider: Provider, chats: [WorkingChat]) {
        self.provider = provider
        var seen: Set<String> = []
        self.chats = chats.filter { seen.insert($0.id).inserted }
    }

    public var displayTitle: String {
        activeCount > 1 ? "\(activeCount) working" : title ?? "Working"
    }
    public func menuLabel(verb: ActivityVerb = .thinking) -> String {
        guard isWorking else { return "" }
        return activeCount > 1 ? "\(activeCount) \(verb.compact)" : verb.compact
    }
}

public protocol ActivityReading: Sendable {
    func read() async -> [ProviderActivity]
}

struct ActivityLogState: Sendable, Equatable {
    var isWorking = false
    var title: String?
}

/// Only lifecycle markers and explicit titles are retained. Message content is never
/// used as a title, displayed, logged or persisted by the activity monitor.
enum ActivityLogParser {
    static func parse(_ data: Data, provider: Provider, previous: ActivityLogState = ActivityLogState()) -> ActivityLogState {
        var state = previous
        for line in data.split(separator: 10) {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = value["type"] as? String else { continue }
            switch provider {
            case .codex:
                let payload = value["payload"] as? [String: Any] ?? [:]
                let event = payload["type"] as? String ?? ""
                if type == "event_msg" {
                    if ["task_started", "turn_started"].contains(event) { state.isWorking = true }
                    if ["task_complete", "task_completed", "turn_complete", "turn_completed", "turn_aborted", "task_failed"].contains(event) {
                        state.isWorking = false
                    }
                } else if type == "response_item" {
                    if ["reasoning", "function_call", "custom_tool_call"].contains(event) { state.isWorking = true }
                    if event == "message", payload["role"] as? String == "assistant" {
                        if payload["phase"] as? String == "final_answer" { state.isWorking = false }
                        else if payload["phase"] as? String == "commentary" { state.isWorking = true }
                    }
                }
            case .claude:
                if value["isSidechain"] as? Bool == true { continue }
                if type == "custom-title", let title = value["customTitle"] as? String {
                    state.title = WorkingChat.sanitizedTitle(title)
                }
                let message = value["message"] as? [String: Any] ?? [:]
                let content = message["content"] as? [[String: Any]] ?? []
                if type == "user", value["isMeta"] as? Bool != true {
                    let toolResultOnly = !content.isEmpty && content.allSatisfy { $0["type"] as? String == "tool_result" }
                    if !toolResultOnly { state.isWorking = true }
                }
                if type == "assistant" {
                    let stop = message["stop_reason"] as? String
                    if stop == "end_turn" || stop == "stop_sequence" { state.isWorking = false }
                    else if stop == "tool_use" || content.contains(where: { $0["type"] as? String == "tool_use" }) { state.isWorking = true }
                }
                if type == "cost-state" { state.isWorking = false }
                if type == "system", let subtype = value["subtype"] as? String,
                   ["turn_duration", "stop_hook_summary"].contains(subtype), value["preventedContinuation"] as? Bool != true {
                    state.isWorking = false
                }
            }
        }
        return state
    }
}
