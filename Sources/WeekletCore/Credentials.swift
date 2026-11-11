import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Security

/// Kept only for the duration of a request. Debug output deliberately redacts all fields.
public struct Credential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let accessToken: String
    let accountID: String?
    public var description: String { "Credential([redacted])" }
    public var debugDescription: String { description }

    init(accessToken: String, accountID: String? = nil) throws {
        guard !accessToken.isEmpty, accessToken.utf8.count <= 32_768,
              accessToken.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }),
              accountID.map({ !$0.isEmpty && $0.utf8.count < 512 && $0.unicodeScalars.allSatisfy { $0.value >= 33 && $0.value <= 126 } }) ?? true
        else { throw UsageFailure.unsupportedAuth }
        self.accessToken = accessToken
        self.accountID = accountID
    }

    func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    func hasSameAccessToken(as other: Credential) -> Bool { accessToken == other.accessToken }
}

public protocol CredentialReading: Sendable {
    func read(for provider: Provider, allowInteraction: Bool) async throws -> Credential
}

public enum CredentialParser {
    private struct ClaudeFile: Decodable {
        struct OAuth: Decodable { let accessToken: String; let expiresAt: Double? }
        let claudeAiOauth: OAuth?
    }
    private struct CodexFile: Decodable {
        struct Tokens: Decodable { let access_token: String; let account_id: String? }
        let tokens: Tokens?
    }
    private struct Expiry: Decodable { let exp: Double? }

    public static func parse(_ data: Data, for provider: Provider, now: Date = Date()) throws -> Credential {
        do {
            switch provider {
            case .claude:
                let root = try JSONDecoder().decode(ClaudeFile.self, from: data)
                guard let oauth = root.claudeAiOauth else { throw UsageFailure.unsupportedAuth }
                if let expiry = oauth.expiresAt, expiry / 1000 <= now.timeIntervalSince1970 {
                    throw UsageFailure.expiredSession
                }
                return try Credential(accessToken: oauth.accessToken)
            case .codex:
                let root = try JSONDecoder().decode(CodexFile.self, from: data)
                guard let tokens = root.tokens else { throw UsageFailure.unsupportedAuth }
                // Decode only the access token's expiry; an ID token is never used for authentication.
                let segments = tokens.access_token.split(separator: ".", omittingEmptySubsequences: false)
                if segments.count == 3 {
                    var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
                    if let data = Data(base64Encoded: payload), let expiry = try? JSONDecoder().decode(Expiry.self, from: data),
                       let exp = expiry.exp, exp <= now.timeIntervalSince1970 { throw UsageFailure.expiredSession }
                }
                return try Credential(accessToken: tokens.access_token, accountID: tokens.account_id)
            }
        } catch let failure as UsageFailure { throw failure }
        catch { throw UsageFailure.unsupportedAuth }
    }
}

/// POSIX reads avoid following a credential-file symlink or opening a non-regular file.
/// No writer, subprocess, login flow or refresh-token model exists in this module.
enum PrivateFile {
    static func read(_ url: URL, requirePrivate: Bool = true) throws -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw UsageFailure.credentialAccess
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_size >= 0, info.st_size <= 1_048_576 else {
            throw UsageFailure.insecureCredentials
        }
        if requirePrivate && (info.st_mode & 0o077) != 0 { throw UsageFailure.insecureCredentials }
        var data = Data(count: Int(info.st_size))
        let count = data.count
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                let length = Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), count - offset)
                if length < 0 && errno == EINTR { continue }
                guard length > 0 else { throw UsageFailure.credentialAccess }
                offset += length
            }
        }
        return data
    }
}

public actor LocalCredentialReader: CredentialReading {
    private let home: URL
    private let codexHome: URL
    private let claudeHome: URL
    private let hasCustomClaudeHome: Bool

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.home = home
        codexHome = Self.directory(environment["CODEX_HOME"], fallback: home.appendingPathComponent(".codex"))
        claudeHome = Self.directory(environment["CLAUDE_CONFIG_DIR"], fallback: home.appendingPathComponent(".claude"))
        hasCustomClaudeHome = claudeHome.standardizedFileURL != home.appendingPathComponent(".claude").standardizedFileURL
    }

    private static func directory(_ path: String?, fallback: URL) -> URL {
        guard let path, path.hasPrefix("/") else { return fallback }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    public func read(for provider: Provider, allowInteraction: Bool) async throws -> Credential {
        try Task.checkCancellation()
        let data: Data?
        switch provider {
        case .claude:
            // Never fall back to a different account's default keychain item for a custom directory.
            if hasCustomClaudeHome {
                data = try PrivateFile.read(claudeHome.appendingPathComponent(".credentials.json"))
            } else {
                data = try Self.keychain(service: "Claude Code-credentials", account: nil, allowInteraction: allowInteraction)
                    ?? PrivateFile.read(claudeHome.appendingPathComponent(".credentials.json"))
            }
        case .codex:
            let mode = try Self.storageMode(at: codexHome.appendingPathComponent("config.toml"))
            switch mode {
            case "ephemeral": throw UsageFailure.notSignedIn
            case "keyring":
                data = try Self.keychain(service: "Codex Auth", account: Self.codexAccount(for: codexHome), allowInteraction: allowInteraction)
            case "auto":
                data = try Self.keychain(service: "Codex Auth", account: Self.codexAccount(for: codexHome), allowInteraction: allowInteraction)
                    ?? PrivateFile.read(codexHome.appendingPathComponent("auth.json"))
            default:
                data = try PrivateFile.read(codexHome.appendingPathComponent("auth.json"))
            }
        }
        guard let data else { throw UsageFailure.notSignedIn }
        return try CredentialParser.parse(data, for: provider)
    }

    static func codexAccount(for directory: URL) -> String {
        let path = directory.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return "codex-" + digest.prefix(16)
    }

    static func storageMode(at url: URL) throws -> String {
        guard let data = try PrivateFile.read(url, requirePrivate: false), let text = String(data: data, encoding: .utf8) else { return "file" }
        // Only the root scalar is relevant. Do not interpret tables, execute helpers or load includes.
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            if trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "cli_auth_credentials_store" || parts[0] == "\"cli_auth_credentials_store\"" else { continue }
            let value = parts[1].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard ["file", "keyring", "auto", "ephemeral"].contains(value) else { throw UsageFailure.unsupportedAuth }
            return value
        }
        return "file"
    }

    private static func keychain(service: String, account: String?, allowInteraction: Bool) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let account { query[kSecAttrAccount as String] = account }
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw UsageFailure.credentialAccess }
        return data
    }
}
