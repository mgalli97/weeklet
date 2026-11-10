import CryptoKit
import Darwin
import Foundation
import Testing
@testable import WeekletCore

final class UpdateTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let paths = ["Weeklet.app/Contents/Info.plist", "Weeklet.app/Contents/MacOS/Weeklet", "Weeklet.app/Contents/MacOS/WeekletInstaller"]

    // Structural ZIP fixtures only; they are never extracted or installed.
    private func zip(extra: [String] = [], mode: UInt32 = 0x81a40000) -> Data {
        func number(_ value: UInt32, _ count: Int) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }) }
        var body = Data(), central = Data()
        for path in paths + extra {
            let name = Data(path.utf8), local = UInt32(body.count)
            body.append(number(0x04034b50, 4)); body.append(number(20, 2)); body.append(Data(repeating: 0, count: 8))
            body.append(Data(repeating: 0, count: 12)); body.append(number(UInt32(name.count), 2)); body.append(number(0, 2)); body.append(name)
            central.append(number(0x02014b50, 4)); central.append(number(0x0314, 2)); central.append(number(20, 2))
            central.append(Data(repeating: 0, count: 20)); central.append(number(UInt32(name.count), 2))
            central.append(Data(repeating: 0, count: 8)); central.append(number(mode, 4)); central.append(number(local, 4)); central.append(name)
        }
        let offset = UInt32(body.count)
        body.append(central); body.append(number(0x06054b50, 4)); body.append(Data(repeating: 0, count: 4))
        body.append(number(UInt32(paths.count + extra.count), 2)); body.append(number(UInt32(paths.count + extra.count), 2))
        body.append(number(UInt32(central.count), 4)); body.append(number(offset, 4)); body.append(number(0, 2))
        return body
    }

    private func signed(_ archive: Data, changes: [String: Any] = [:]) throws -> Data {
        let release = UpdateRelease(version: "1.1.0", build: 2, architecture: "arm64", sourceCommit: String(repeating: "a", count: 40),
                                    archiveSize: archive.count, archiveSHA256: SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined())
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(release)) as! [String: Any]
        for (field, replacement) in changes { value[field] = replacement }
        let payload = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try JSONEncoder().encode(SignedUpdateEnvelope(payload: payload, signature: key.signature(for: payload)))
    }

    private func verified(_ envelope: Data) throws -> VerifiedUpdate {
        try VerifiedUpdate.verify(envelope, publicKey: key.publicKey.rawRepresentation)
    }

    @Test func testPublisherSignatureAndArchiveDigestAreVerified() throws {
        let archive = zip()
        let update = try verified(signed(archive))
        checkEqual(update.release.version, "1.1.0")
        try update.verifyArchive(archive)
    }

    @Test func testDifferentPublisherKeyIsRejected() throws {
        let envelope = try signed(zip())
        checkThrowsError(try VerifiedUpdate.verify(envelope, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation))
    }

    @Test func testPayloadCannotChangeAfterSigning() throws {
        let envelope = try signed(zip())
        let decoded = try JSONDecoder().decode(SignedUpdateEnvelope.self, from: envelope)
        var payload = Data(base64Encoded: decoded.payload)!
        payload[payload.count / 2] ^= 1
        let changed = try JSONEncoder().encode(SignedUpdateEnvelope(payload: payload, signature: Data(base64Encoded: decoded.signature)!))
        checkThrowsError(try verified(changed))
    }

    @Test func testMalformedAndOversizedEnvelopesFailClosed() {
        for body in [Data("{}".utf8), Data("{\"schema\":1,\"payload\":\"!\",\"signature\":\"!\"}".utf8), Data(repeating: 0, count: 65_537)] {
            checkThrowsError(try verified(body))
        }
        checkThrowsError(try VerifiedUpdate.verify(Data(), publicKey: Data(repeating: 0, count: 31)))
    }

    @Test func testSignedMetadataStillHasToMatchTheRepositoryContract() throws {
        for changes: [String: Any] in [["schema": 2], ["build": 0], ["version": "../escape"], ["version": "01.1.0"],
                                       ["minimumSystemVersion": "tomorrow"], ["sourceCommit": "not-a-commit"],
                                       ["archiveSHA256": String(repeating: "A", count: 64)], ["archiveSize": 0],
                                       ["archiveSize": UpdateTrust.maximumArchiveSize + 1], ["architecture": "other"],
                                       ["archiveURL": "https://example.com/app.zip"],
                                       ["archiveURL": "https://github.com/mgalli97/weeklet/releases/download/v1.1.0/Weeklet-macOS-arm64.zip?redirect=1"]] {
            checkThrowsError(try verified(signed(zip(), changes: changes)))
        }
    }

    @Test func testArchiveTamperingAndTruncationAreRejected() throws {
        let archive = zip()
        let update = try verified(signed(archive))
        var changed = archive; changed[5] ^= 1
        checkThrowsError(try update.verifyArchive(changed))
        checkThrowsError(try update.verifyArchive(Data(archive.dropLast())))
    }

    @Test func testVersionComparisonIsNumericAndRejectsDowngrades() throws {
        checkEqual(try ReleaseVersion("1.10.0") > ReleaseVersion("1.9.9"), true)
        let release = try verified(signed(zip())).release
        checkEqual(try release.isNewer(than: 1, version: "1.0.0"), true)
        checkEqual(try release.isNewer(than: 2, version: "1.0.0"), false)
        checkEqual(try release.isNewer(than: 1, version: "2.0.0"), false)
        checkEqual(try release.isNewer(than: 1, version: "1.1.0"), false)
        for bad in ["1", "1.0", "v1.0.0", "1.0.0-beta", "1.0.-1", "1.0.0.0", "1.4294967296.0", "1. 0.0"] {
            checkThrowsError(try ReleaseVersion(bad))
        }
    }

    @Test func testArchitectureAndMinimumSystemAreEnforced() throws {
        let release = try verified(signed(zip())).release
        checkEqual(try release.supports(architecture: "arm64", systemVersion: "14.0.0"), true)
        checkEqual(try release.supports(architecture: "arm64", systemVersion: "13.9.0"), false)
        checkEqual(try release.supports(architecture: "x86_64", systemVersion: "26.0.0"), false)
        let universal = try verified(signed(zip(), changes: ["architecture": "universal", "archiveURL": "https://github.com/mgalli97/weeklet/releases/download/v1.1.0/Weeklet-macOS-universal.zip"])).release
        checkEqual(try universal.supports(architecture: "x86_64", systemVersion: "14.0.0"), true)
    }

    @Test func testZipCannotEscapeTheAppBundle() {
        for path in ["../escape", "/tmp/escape", "Weeklet.app/../escape", "Weeklet.app//escape", "Weeklet.app/./escape",
                     "Other.app/Contents/test", "Weeklet.app/Contents/../escape", "Weeklet.app/Contents/a\\b", "Weeklet.app/Contents/a:b"] {
            checkThrowsError(try UpdateArchive.validate(zip(extra: [path])))
        }
    }

    @Test func testZipSymlinksAndCaseCollisionsAreRejected() {
        checkThrowsError(try UpdateArchive.validate(zip(mode: 0xa1ff0000)))
        checkThrowsError(try UpdateArchive.validate(zip(extra: ["weeklet.app/contents/info.plist"])))
        checkThrowsError(try UpdateArchive.validate(zip(extra: [paths[0]])))
    }

    @Test func testTruncatedZipHeadersAndOutOfRangeOffsetsDoNotCrash() {
        let archive = zip()
        for count in [0, 1, 10, 21, archive.count - 1, archive.count / 2] {
            checkThrowsError(try UpdateArchive.validate(Data(archive.prefix(count))))
        }
        var changed = archive
        for index in (changed.count - 6)..<(changed.count - 2) { changed[index] = 255 }
        checkThrowsError(try UpdateArchive.validate(changed))
    }

    @Test func testLocalAndCentralZipNamesMustAgree() {
        var archive = zip()
        archive[30] = 88
        checkThrowsError(try UpdateArchive.validate(archive))
    }

    @Test func testZipEncryptionAndUnsupportedCompressionAreRejected() {
        let original = zip()
        let central = original.firstRange(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        var encrypted = original; encrypted[central + 8] = 1
        checkThrowsError(try UpdateArchive.validate(encrypted))
        var unsupported = original; unsupported[central + 10] = 99
        checkThrowsError(try UpdateArchive.validate(unsupported))
    }

    @Test func testExpandedArchiveSizeIsBounded() {
        var archive = zip()
        let central = archive.firstRange(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        for index in 0..<4 { archive[central + 24 + index] = 0xfe }
        checkThrowsError(try UpdateArchive.validate(archive))
    }

    @Test func testOnlyFixedGitHubHTTPSHostsAreAllowed() {
        for url in ["https://github.com/mgalli97/weeklet", "https://release-assets.githubusercontent.com/file", "https://objects.githubusercontent.com/file"] {
            checkEqual(UpdateURLs.allows(URL(string: url)!), true)
        }
        for url in ["http://github.com/file", "https://github.com.evil.test/file", "https://github.com:8443/file", "https://user:password@github.com/file", "file:///tmp/update.zip"] {
            checkFalse(UpdateURLs.allows(URL(string: url)!))
        }
    }

    @Test func testUpdateWorkspaceIsOwnedPrivateAndRefusesSymlinkFiles() throws {
        let folder = try UpdateWorkspace.create()
        defer { try? FileManager.default.removeItem(at: folder) }
        try UpdateWorkspace.write(Data("safe".utf8), name: "update.json", in: folder)
        checkEqual(try UpdateWorkspace.read("update.json", in: folder, maximum: 20), Data("safe".utf8))
        checkThrowsError(try UpdateWorkspace.read("update.json", in: folder, maximum: 1))
        checkThrowsError(try UpdateWorkspace.validate(folder.appendingPathComponent("..")))
        let file = folder.appendingPathComponent("update.json")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("archive.zip"), withDestinationURL: file)
        checkThrowsError(try UpdateWorkspace.read("archive.zip", in: folder, maximum: 20))
        chmod(file.path, 0o644)
        checkThrowsError(try UpdateWorkspace.read("update.json", in: folder, maximum: 20))
    }

    @Test func testInstallerEnvironmentNeverInheritsAuthenticationSecrets() {
        let source = ["CODEX_HOME": "/tmp/custom-codex", "CLAUDE_CONFIG_DIR": "/tmp/custom-claude",
                      "OPENAI_API_KEY": "synthetic", "ANTHROPIC_API_KEY": "synthetic",
                      "CODEX_ACCESS_TOKEN": "synthetic", "GH_TOKEN": "synthetic", "GITHUB_TOKEN": "synthetic",
                      "AWS_SECRET_ACCESS_KEY": "synthetic", "PATH": "/tmp/untrusted-bin"]
        let result = UpdateEnvironment.installer(from: source, temporaryDirectory: URL(fileURLWithPath: "/tmp"))
        checkEqual(Set(result.keys), Set(["PATH", "TMPDIR", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]))
        checkEqual(result["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin")
        checkEqual(result["CODEX_HOME"], "/tmp/custom-codex")
        let invalid = UpdateEnvironment.installer(from: ["CODEX_HOME": "relative", "CLAUDE_CONFIG_DIR": "/tmp/unsafe\nvalue"],
                                                  temporaryDirectory: URL(fileURLWithPath: "/tmp"))
        checkEqual(Set(invalid.keys), Set(["PATH", "TMPDIR"]))
    }
}
