import Darwin
import Foundation
import Testing
@testable import WeekletCore

final class CredentialTests {
    private let now = Date(timeIntervalSince1970: 2_000)

    @Test func testClaudeDecodesOnlyAccessToken() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"test-access","expiresAt":3000000,"refreshToken":"never-use"}}"#.utf8)
        let credential = try CredentialParser.parse(data, for: .claude, now: now)
        checkEqual(credential.description, "Credential([redacted])")
        checkEqual(credential.debugDescription, "Credential([redacted])")
        var request = URLRequest(url: Provider.claude.usageURL)
        credential.authorize(&request)
        checkEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
    }

    @Test func testExpiredClaudeTokenIsNeverUsed() {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"test-access","expiresAt":1000000}}"#.utf8)
        checkThrowsError(try CredentialParser.parse(data, for: .claude, now: now)) {
            checkEqual($0 as? UsageFailure, .expiredSession)
        }
    }

    @Test func testCodexRejectsExpiredAccessJWT() {
        let payload = Data(#"{"exp":1000}"#.utf8).base64EncodedString()
        let data = Data("{\"tokens\":{\"access_token\":\"header.\(payload).signature\",\"account_id\":\"test-account\"}}".utf8)
        checkThrowsError(try CredentialParser.parse(data, for: .codex, now: now)) {
            checkEqual($0 as? UsageFailure, .expiredSession)
        }
    }

    @Test func testIDTokensAndAPIKeysCannotSubstituteAccessToken() {
        for text in [#"{"OPENAI_API_KEY":"test-key"}"#, #"{"tokens":{"id_token":"test-id","refresh_token":"never-use"}}"#] {
            checkThrowsError(try CredentialParser.parse(Data(text.utf8), for: .codex))
        }
    }

    @Test func testHeaderInjectionIsRejected() {
        checkThrowsError(try Credential(accessToken: "token\r\nInjected: true"))
        checkThrowsError(try Credential(accessToken: "token", accountID: "account\nInjected: true"))
        checkThrowsError(try Credential(accessToken: ""))
        checkThrowsError(try Credential(accessToken: "token\u{0}suffix"))
    }

    @Test func testPrivateFileReadIsReadOnlyAndRefusesSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("test.json")
        let content = Data("synthetic credential".utf8)
        try content.write(to: file)
        chmod(file.path, 0o600)
        let before = try FileManager.default.attributesOfItem(atPath: file.path)
        checkEqual(try PrivateFile.read(file), content)
        let after = try FileManager.default.attributesOfItem(atPath: file.path)
        checkEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        checkThrowsError(try PrivateFile.read(link))
        chmod(file.path, 0o644)
        checkThrowsError(try PrivateFile.read(file)) { checkEqual($0 as? UsageFailure, .insecureCredentials) }
    }

    @Test func testStorageModeIgnoresCommentsAndNestedTables() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        for (text, expected) in [
            ("# cli_auth_credentials_store = \"keyring\"\n[profile]\ncli_auth_credentials_store = \"keyring\"", "file"),
            ("cli_auth_credentials_store = 'auto' # comment", "auto"),
            ("\"cli_auth_credentials_store\" = \"ephemeral\"", "ephemeral")
        ] {
            try Data(text.utf8).write(to: file)
            checkEqual(try LocalCredentialReader.storageMode(at: file), expected)
        }
        try Data("cli_auth_credentials_store = # missing".utf8).write(to: file)
        checkThrowsError(try LocalCredentialReader.storageMode(at: file))
    }

    @Test func testCodexAccountIsStableAndUsesCanonicalHome() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let direct = LocalCredentialReader.codexAccount(for: directory)
        checkEqual(direct.count, 22)
        checkEqual(direct, LocalCredentialReader.codexAccount(for: link))
    }
}
