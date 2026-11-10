import CryptoKit
import Foundation
import Security
import WeekletCore

@main
enum ReleaseMain {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["key"] {
                print(try signingKey().publicKey.rawRepresentation.base64EncodedString())
                return
            }
            if args.count == 2, args[0] == "verify" {
                _ = try VerifiedUpdate.verify(Data(contentsOf: URL(fileURLWithPath: args[1])))
                print("Verified publisher signature.")
                return
            }
            guard args.count == 6, args[0] == "sign", let build = UInt64(args[3]) else {
                fputs("Usage: WeekletRelease key | verify MANIFEST | sign ARCHIVE VERSION BUILD SOURCE_SHA OUTPUT\n", stderr); exit(1)
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
            try UpdateArchive.validate(data)
            let release = UpdateRelease(version: args[2], build: build, architecture: UpdateTrust.architecture,
                                        sourceCommit: args[4], archiveSize: data.count,
                                        archiveSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            try release.validate()
            let key = try signingKey()
            guard key.publicKey.rawRepresentation.base64EncodedString() == UpdateTrust.publicKeyBase64 else { throw UpdateFailure.invalidSignature }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            let payload = try encoder.encode(release)
            let envelope = SignedUpdateEnvelope(payload: payload, signature: try key.signature(for: payload))
            let output = try encoder.encode(envelope)
            _ = try VerifiedUpdate.verify(output)
            try output.write(to: URL(fileURLWithPath: args[5]), options: .atomic)
            print("Signed Weeklet \(release.version) (\(release.build)); private key remains in Keychain.")
        } catch {
            fputs("Release preparation failed. Check the archive, version and local signing key.\n", stderr)
            exit(1)
        }
    }

    private static func signingKey() throws -> Curve25519.Signing.PrivateKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Weeklet Release Signing", kSecAttrAccount as String: "com.mgalli97.weeklet.ed25519",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            throw UpdateFailure.invalidSignature
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }
}
