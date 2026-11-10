import Darwin
import Foundation

public enum UpdateEnvironment {
    public static func installer(from source: [String: String], temporaryDirectory: URL) -> [String: String] {
        var result = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": temporaryDirectory.path]
        for key in ["CODEX_HOME", "CLAUDE_CONFIG_DIR"] {
            if let value = source[key], value.hasPrefix("/"), value.utf8.count <= 4096,
               !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                result[key] = value
            }
        }
        return result
    }
}

public enum UpdateURLs {
    public static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }
}

private final class UpdateRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.httpMethod == "GET" && request.url.map(UpdateURLs.allows) == true ? request : nil)
    }
}

/// This session never reads provider credentials or sends an Authorization header.
public actor GitHubUpdates {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 180
        session = URLSession(configuration: config, delegate: UpdateRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func check() async throws -> VerifiedUpdate {
        try VerifiedUpdate.verify(await get(UpdateTrust.feed, maximum: 65_536))
    }

    public func download(_ update: VerifiedUpdate) async throws -> URL {
        let body = try await get(URL(string: update.release.archiveURL)!, maximum: update.release.archiveSize)
        try update.verifyArchive(body)
        let folder = try UpdateWorkspace.create()
        do {
            try UpdateWorkspace.write(update.envelope, name: "update.json", in: folder)
            try UpdateWorkspace.write(body, name: "archive.zip", in: folder)
            return folder
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw UpdateFailure.installationFailed
        }
    }

    private func get(_ url: URL, maximum: Int) async throws -> Data {
        guard UpdateURLs.allows(url), maximum > 0, maximum <= UpdateTrust.maximumArchiveSize else { throw UpdateFailure.invalidManifest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Weeklet", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url.map(UpdateURLs.allows) == true else { throw UpdateFailure.unavailable }
        guard response.expectedContentLength <= maximum else { throw UpdateFailure.invalidArchive }
        var body = Data()
        body.reserveCapacity(min(maximum, 1_048_576))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard body.count < maximum else { throw UpdateFailure.invalidArchive }
            body.append(byte)
        }
        return body
    }
}

public enum UpdateWorkspace {
    public static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("WeekletUpdates", isDirectory: true).standardizedFileURL }

    public static func create() throws -> URL {
        let manager = FileManager.default
        if !manager.fileExists(atPath: root.path) {
            try manager.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        try checkDirectory(root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return folder
    }

    public static func validate(_ folder: URL) throws {
        let clean = folder.standardizedFileURL
        guard clean.deletingLastPathComponent().path == root.path,
              UUID(uuidString: clean.lastPathComponent) != nil else { throw UpdateFailure.installationFailed }
        try checkDirectory(root)
        try checkDirectory(clean)
    }

    public static func write(_ data: Data, name: String, in folder: URL) throws {
        try validate(folder)
        guard ["update.json", "archive.zip", "ready", "failed"].contains(name) else { throw UpdateFailure.installationFailed }
        let file = folder.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public static func read(_ name: String, in folder: URL, maximum: Int) throws -> Data? {
        try validate(folder)
        guard ["update.json", "archive.zip", "ready", "failed"].contains(name) else { throw UpdateFailure.installationFailed }
        let fd = open(folder.appendingPathComponent(name).path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw UpdateFailure.installationFailed
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, info.st_size >= 0, info.st_size <= maximum else { throw UpdateFailure.installationFailed }
        var result = Data(count: Int(info.st_size))
        let count = result.count
        try result.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let read = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset)
                if read < 0, errno == EINTR { continue }
                guard read > 0 else { throw UpdateFailure.installationFailed }
                offset += read
            }
        }
        return result
    }

    private static func checkDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw UpdateFailure.installationFailed }
    }
}
