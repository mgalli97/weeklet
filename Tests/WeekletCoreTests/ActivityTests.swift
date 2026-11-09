import Foundation
import SQLite3
import Testing
@testable import WeekletCore

private actor TestActivityReader: ActivityReading {
    private(set) var calls = 0
    func read() async -> [ProviderActivity] {
        calls += 1
        return [ProviderActivity(provider: .claude), ProviderActivity(provider: .codex, isWorking: true, title: "Build interface")]
    }
}

final class ActivityTests {
    private func data(_ rows: String...) -> Data { Data((rows.joined(separator: "\n") + "\n").utf8) }

    @Test func testCodexStartAndCompletionSignals() {
        let start = ActivityLogParser.parse(data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#), provider: .codex)
        checkEqual(start.isWorking, true)
        for event in ["task_complete", "turn_aborted", "task_failed"] {
            let end = ActivityLogParser.parse(data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"\(event)\"}}"), provider: .codex, previous: start)
            checkFalse(end.isWorking)
        }
    }

    @Test func testCodexFinalAnswerStopsTheIndicator() {
        let value = ActivityLogParser.parse(data(
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer"}}"#
        ), provider: .codex)
        checkFalse(value.isWorking)
    }

    @Test func testCodexCanDetectWorkInABoundedMidTurnTail() {
        for event in ["reasoning", "function_call", "custom_tool_call"] {
            let value = ActivityLogParser.parse(data("{\"type\":\"response_item\",\"payload\":{\"type\":\"\(event)\"}}"), provider: .codex)
            checkEqual(value.isWorking, true)
        }
    }

    @Test func testClaudeUserToolAndFinalLifecycle() {
        let value = ActivityLogParser.parse(data(
            #"{"type":"user","message":{"content":"synthetic prompt"}}"#,
            #"{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#
        ), provider: .claude)
        checkEqual(value.isWorking, true)
        let ended = ActivityLogParser.parse(data(#"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#), provider: .claude, previous: value)
        checkFalse(ended.isWorking)
    }

    @Test func testClaudeStopHookMayContinueWork() {
        let working = ActivityLogState(isWorking: true)
        let continued = ActivityLogParser.parse(data(#"{"type":"system","subtype":"stop_hook_summary","preventedContinuation":true}"#), provider: .claude, previous: working)
        checkEqual(continued.isWorking, true)
        let stopped = ActivityLogParser.parse(data(#"{"type":"system","subtype":"stop_hook_summary","preventedContinuation":false}"#), provider: .claude, previous: working)
        checkFalse(stopped.isWorking)
    }

    @Test func testOnlyExplicitMetadataBecomesATitle() {
        let noTitle = ActivityLogParser.parse(data(#"{"type":"last-prompt","lastPrompt":"not a title"}"#), provider: .claude)
        checkNil(noTitle.title)
        let named = ActivityLogParser.parse(data(#"{"type":"custom-title","customTitle":"Build settings"}"#), provider: .claude)
        checkEqual(named.title, "Build settings")
    }

    @Test func testClaudeSidechainDoesNotStartMainSessionWork() {
        let value = ActivityLogParser.parse(data(#"{"type":"user","isSidechain":true,"message":{"content":"synthetic"}}"#), provider: .claude)
        checkFalse(value.isWorking)
    }

    @Test func testActivityTitleIsSmallAndSanitized() {
        let activity = ProviderActivity(provider: .codex, isWorking: true, title: "\n Build\u{0}   settings \t")
        checkEqual(activity.displayTitle, "Build settings")
        checkEqual(activity.menuLabel(verb: .brewing), "brew…")
        checkEqual(ProviderActivity(provider: .claude, isWorking: true).displayTitle, "Working")
    }

    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeCodexDatabase(home: URL, transcript: URL, source: String = "vscode") throws {
        let path = home.appendingPathComponent(".codex/state_5.sqlite").path
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(handle) }
        let escapedPath = transcript.path.replacingOccurrences(of: "'", with: "''")
        let escapedSource = source.replacingOccurrences(of: "'", with: "''")
        let sql = "CREATE TABLE threads (name TEXT, title TEXT, rollout_path TEXT, archived INTEGER, has_user_event INTEGER, updated_at INTEGER, source TEXT); INSERT INTO threads VALUES ('Build settings', 'Fallback title', '\(escapedPath)', 0, 0, 1, '\(escapedSource)');"
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
    }

    @Test func testCodexReaderReadsMetadataWithoutChangingTheDatabase() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let transcript = sessions.appendingPathComponent("synthetic.jsonl")
        try data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#).write(to: transcript)
        try makeCodexDatabase(home: home, transcript: transcript)
        let database = home.appendingPathComponent(".codex/state_5.sqlite")
        let before = try Data(contentsOf: database)
        let reader = LocalActivityReader(home: home, environment: [:])
        let activity = await reader.read().first { $0.provider == .codex }
        checkEqual(activity?.isWorking, true)
        checkEqual(activity?.title, "Build settings")
        checkEqual(try Data(contentsOf: database), before)
        try data(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#).write(to: transcript)
        let stopped = await reader.read().first { $0.provider == .codex }
        checkEqual(stopped?.isWorking, false)
    }

    @Test func testAbandonedActivityExpiresInsteadOfWorkingForever() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let transcript = sessions.appendingPathComponent("synthetic.jsonl")
        try data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#).write(to: transcript)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-1000)], ofItemAtPath: transcript.path)
        try makeCodexDatabase(home: home, transcript: transcript)
        let activity = await LocalActivityReader(home: home, environment: [:]).read()
        checkFalse(activity.contains(where: \.isWorking))
    }

    @Test func testClaudeReaderUsesTheCustomTitleAndStopsOnCostState() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent(".claude/projects/synthetic")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let transcript = project.appendingPathComponent("session.jsonl")
        try data(#"{"type":"custom-title","customTitle":"Design panel"}"#,
                 #"{"type":"user","message":{"content":"not displayed"}}"#).write(to: transcript)
        let reader = LocalActivityReader(home: home, environment: [:])
        let activity = await reader.read().first { $0.provider == .claude }
        checkEqual(activity?.isWorking, true)
        checkEqual(activity?.title, "Design panel")
        try data(#"{"type":"cost-state"}"#).write(to: transcript)
        let stopped = await reader.read().first { $0.provider == .claude }
        checkEqual(stopped?.isWorking, false)
    }

    @Test func testUnavailableSourcesProduceIdleStates() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let activity = await LocalActivityReader(home: home, environment: [:]).read()
        checkEqual(activity.count, 2)
        checkFalse(activity.contains(where: \.isWorking))
    }

    @Test func testCodexSubagentsDoNotReplaceTheUserChatTitle() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let transcript = sessions.appendingPathComponent("synthetic.jsonl")
        try data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#).write(to: transcript)
        try makeCodexDatabase(home: home, transcript: transcript, source: #"{"subagent":{"parent_thread_id":"synthetic"}}"#)
        let activity = await LocalActivityReader(home: home, environment: [:]).read()
        checkFalse(activity.contains(where: \.isWorking))
    }

    @Test @MainActor func testActivityRefreshesAreCoalesced() async {
        let reader = TestActivityReader()
        let store = ActivityStore(reader: reader)
        store.refresh()
        store.refresh()
        await store.waitForRefresh()
        let calls = await reader.calls
        checkEqual(calls, 1)
        checkEqual(store.states.last?.menuLabel(), "think…")
        store.stop()
    }

    @Test func testSeveralChatsHaveAnExplicitWorkingCount() {
        let state = ProviderActivity(provider: .codex, chats: [
            WorkingChat(id: "first", title: "First chat"), WorkingChat(id: "second", title: "Second chat")
        ])
        checkEqual(state.activeCount, 2)
        checkEqual(state.menuLabel(verb: .cooking), "2 cook…")
        checkEqual(state.title, "First chat")
    }

    @Test func testDuplicateSessionIDsAreNotCountedTwice() {
        let state = ProviderActivity(provider: .claude, chats: [
            WorkingChat(id: "same-session", title: "Latest title"), WorkingChat(id: "same-session", title: "Old title")
        ])
        checkEqual(state.activeCount, 1)
        checkEqual(state.title, "Latest title")
    }

    @Test func testCodexReaderCountsChatsAndRemovesCompletedOnes() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let first = sessions.appendingPathComponent("first.jsonl")
        let second = sessions.appendingPathComponent("second.jsonl")
        for file in [first, second] { try data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#).write(to: file) }
        try makeCodexDatabase(home: home, transcript: first)
        var handle: OpaquePointer?
        guard sqlite3_open(home.appendingPathComponent(".codex/state_5.sqlite").path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        let path = second.path.replacingOccurrences(of: "'", with: "''")
        let sql = "INSERT INTO threads VALUES ('Second task', 'Fallback', '\(path)', 0, 0, 2, 'vscode');"
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        sqlite3_close(handle)
        checkEqual(result, SQLITE_OK)
        let reader = LocalActivityReader(home: home, environment: [:])
        let both = await reader.read().first { $0.provider == .codex }
        checkEqual(both?.activeCount, 2)
        try data(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#).write(to: second)
        let remaining = await reader.read().first { $0.provider == .codex }
        checkEqual(remaining?.activeCount, 1)
        checkEqual(remaining?.title, "Build settings")
    }

    @Test func testProgressWordsStayCompactAndCycle() {
        checkEqual(ActivityVerb.thinking.compact, "think…")
        checkEqual(ActivityVerb.baking.next, .thinking)
        for verb in ActivityVerb.allCases {
            checkEqual(verb.compact.hasSuffix("…"), true)
            checkEqual(verb.compact.count <= 6, true)
        }
    }

    @Test @MainActor func testWordsRotateOnlyDuringActiveWork() async {
        let store = ActivityStore(reader: TestActivityReader())
        store.refresh()
        await store.waitForRefresh()
        for _ in 0..<8 { store.advancePulse() }
        checkEqual(store.verb, .brewing)
        store.stop()
        for _ in 0..<8 { store.advancePulse() }
        checkEqual(store.verb, .brewing)
    }

    @Test @MainActor func testIdleActivityDoesNotAnimateOrRotate() {
        let store = ActivityStore(reader: TestActivityReader())
        for _ in 0..<16 { store.advancePulse() }
        checkEqual(store.verb, .thinking)
        checkEqual(store.pulse, true)
    }
}
