import Darwin
import Foundation
import SQLite3

public actor LocalActivityReader: ActivityReading {
    private struct Candidate {
        let url: URL
        let title: String?
    }
    private struct Stamp: Equatable {
        let inode: UInt64
        let size: Int64
        let modified: Date
    }
    private struct CachedLog {
        let stamp: Stamp
        let state: ActivityLogState
    }
    private let codexHome: URL
    private let claudeHome: URL
    private var cache: [URL: CachedLog] = [:]
    private var databaseStamp: [Date?] = []
    private var codexCandidates: [Candidate] = []
    private var claudeCandidates: [Candidate] = []
    private var lastClaudeScan = Date.distantPast
    private let maximumTail = 262_144

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        func directory(_ key: String, fallback: String) -> URL {
            guard let value = environment[key], value.hasPrefix("/") else { return home.appendingPathComponent(fallback) }
            return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
        }
        codexHome = directory("CODEX_HOME", fallback: ".codex")
        claudeHome = directory("CLAUDE_CONFIG_DIR", fallback: ".claude")
    }

    public func read() async -> [ProviderActivity] {
        let now = Date()
        refreshCodexIndex()
        if now.timeIntervalSince(lastClaudeScan) >= 15 {
            claudeCandidates = scanClaudeProjects()
            lastClaudeScan = now
        }
        let all = Set((codexCandidates + claudeCandidates).map(\.url))
        cache = cache.filter { all.contains($0.key) }
        return [activity(.claude, candidates: claudeCandidates, now: now),
                activity(.codex, candidates: codexCandidates, now: now)]
    }

    private func activity(_ provider: Provider, candidates: [Candidate], now: Date) -> ProviderActivity {
        var working: [(Date, WorkingChat)] = []
        for candidate in candidates {
            guard let log = readLog(candidate.url, provider: provider), log.state.isWorking,
                  now.timeIntervalSince(log.stamp.modified) < 900 else { continue }
            let id = candidate.url.deletingPathExtension().lastPathComponent
            working.append((log.stamp.modified, WorkingChat(id: id, title: log.state.title ?? candidate.title)))
        }
        return ProviderActivity(provider: provider, chats: working.sorted { $0.0 > $1.0 }.map(\.1))
    }

    private func readLog(_ url: URL, provider: Provider) -> CachedLog? {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        let stamp = Stamp(inode: UInt64(info.st_ino), size: info.st_size, modified: modified)
        if let previous = cache[url], previous.stamp == stamp { return previous }
        let count = min(maximumTail, max(0, Int(info.st_size)))
        let start = max(0, info.st_size - off_t(count))
        var data = Data(count: count)
        let readCount = data.withUnsafeMutableBytes { buffer in
            pread(fd, buffer.baseAddress, count, start)
        }
        guard readCount >= 0 else { return nil }
        data = Data(data.prefix(readCount))
        if start > 0, let newline = data.firstIndex(of: 10) { data = Data(data.suffix(from: data.index(after: newline))) }
        let previous = cache[url]
        let canContinue = previous?.stamp.inode == stamp.inode && (previous?.stamp.size ?? 0) <= stamp.size
        let state = ActivityLogParser.parse(data, provider: provider, previous: canContinue ? previous!.state : ActivityLogState())
        let result = CachedLog(stamp: stamp, state: state)
        cache[url] = result
        return result
    }

    private func refreshCodexIndex() {
        let database = codexHome.appendingPathComponent("state_5.sqlite")
        let files = [database, URL(fileURLWithPath: database.path + "-wal")]
        let stamps = files.map { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        guard stamps != databaseStamp else { return }
        databaseStamp = stamps
        var info = stat()
        guard lstat(database.path, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG else { return }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            return
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 100)
        sqlite3_exec(handle, "PRAGMA query_only = ON", nil, nil, nil)
        // Desktop user chats can have has_user_event = 0; exclude subagents by source instead.
        let queries = [
            "SELECT COALESCE(NULLIF(name, ''), title), rollout_path, source FROM threads WHERE archived = 0 ORDER BY updated_at DESC LIMIT 32",
            "SELECT title, rollout_path, source FROM threads WHERE archived = 0 ORDER BY updated_at DESC LIMIT 32"
        ]
        var statement: OpaquePointer?
        for query in queries {
            if sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK { break }
            if let statement { sqlite3_finalize(statement) }
            statement = nil
        }
        guard let statement else { return }
        defer { sqlite3_finalize(statement) }
        let root = codexHome.appendingPathComponent("sessions", isDirectory: true).standardizedFileURL.path + "/"
        var candidates: [Candidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let source = sqlite3_column_text(statement, 2) {
                let text = String(cString: source)
                if let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   value["subagent"] != nil { continue }
            }
            guard let path = sqlite3_column_text(statement, 1) else { continue }
            let url = URL(fileURLWithPath: String(cString: path)).standardizedFileURL
            guard url.path.hasPrefix(root), url.pathExtension == "jsonl" else { continue }
            let title = WorkingChat.sanitizedTitle(sqlite3_column_text(statement, 0).map { String(cString: $0) })
            candidates.append(Candidate(url: url, title: title))
            if candidates.count == 16 { break }
        }
        codexCandidates = candidates
    }

    private func scanClaudeProjects() -> [Candidate] {
        let manager = FileManager.default
        let root = claudeHome.appendingPathComponent("projects", isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let directories = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        let recent = directories.compactMap { url -> (URL, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }.prefix(8)
        var files: [(URL, Date)] = []
        var titles: [String: String] = [:]
        for (directory, _) in recent {
            let index = directory.appendingPathComponent("sessions-index.json")
            if let attributes = try? manager.attributesOfItem(atPath: index.path), (attributes[.size] as? Int ?? Int.max) <= 524_288,
               let data = try? PrivateFile.read(index, requirePrivate: false),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let entries = root["entries"] as? [[String: Any]] {
                for entry in entries where entry["isSidechain"] as? Bool != true {
                    if let id = entry["sessionId"] as? String, let title = entry["summary"] as? String {
                        titles[id] = WorkingChat.sanitizedTitle(title)
                    }
                }
            }
            let children = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for url in children where url.pathExtension == "jsonl" {
                if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate { files.append((url, date)) }
            }
        }
        return files.sorted { $0.1 > $1.1 }.prefix(16).map { Candidate(url: $0.0, title: titles[$0.0.deletingPathExtension().lastPathComponent]) }
    }
}
