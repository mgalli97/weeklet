import CryptoKit
import Foundation

public enum UpdateTrust {
    public static let publicKeyBase64 = "DU0WRgEkVRjpr3/cjta/qXGIE93rrpit90NtUgp+ZQk="
    public static let repository = "mgalli97/weeklet"
    public static let bundleIdentifier = "com.mgalli97.weeklet"
    public static let feed = URL(string: "https://github.com/mgalli97/weeklet/releases/latest/download/update.json")!
    public static let maximumArchiveSize = 67_108_864
    public static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

public enum UpdateFailure: Error, Sendable, Equatable {
    case unavailable, network, invalidManifest, invalidSignature, invalidArchive
    case unsupportedSystem, unsupportedArchitecture, notWritable, installationFailed

    public var message: String {
        switch self {
        case .unavailable: "Updates are not available yet."
        case .network: "Could not check for updates."
        case .invalidManifest, .invalidSignature: "Update verification failed."
        case .invalidArchive: "The update download could not be verified."
        case .unsupportedSystem: "This update needs a newer macOS version."
        case .unsupportedArchitecture: "No update is available for this Mac."
        case .notWritable: "Move Weeklet to a writable Applications folder."
        case .installationFailed: "Could not install the update. Please try again."
        }
    }
}

public struct ReleaseVersion: Sendable, Equatable, Comparable {
    public let text: String
    private let components: [UInt32]

    public init(_ text: String) throws {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard text.utf8.count <= 32, pieces.count == 3 else { throw UpdateFailure.invalidManifest }
        var values: [UInt32] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.utf8.allSatisfy({ (48...57).contains($0) }),
                  piece.count == 1 || piece.first != "0", let value = UInt32(piece) else { throw UpdateFailure.invalidManifest }
            values.append(value)
        }
        self.text = text
        components = values
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct UpdateRelease: Codable, Sendable, Equatable {
    public let schema: Int
    public let version: String
    public let build: UInt64
    public let minimumSystemVersion: String
    public let architecture: String
    public let sourceCommit: String
    public let archiveURL: String
    public let archiveSize: Int
    public let archiveSHA256: String

    public init(version: String, build: UInt64, architecture: String, sourceCommit: String,
                archiveSize: Int, archiveSHA256: String) {
        schema = 1
        self.version = version
        self.build = build
        minimumSystemVersion = "14.0.0"
        self.architecture = architecture
        self.sourceCommit = sourceCommit
        archiveURL = "https://github.com/\(UpdateTrust.repository)/releases/download/v\(version)/Weeklet-macOS-\(architecture).zip"
        self.archiveSize = archiveSize
        self.archiveSHA256 = archiveSHA256
    }

    public func validate() throws {
        _ = try ReleaseVersion(version)
        _ = try ReleaseVersion(minimumSystemVersion)
        let expected = "https://github.com/\(UpdateTrust.repository)/releases/download/v\(version)/Weeklet-macOS-\(architecture).zip"
        guard schema == 1, build > 0, ["arm64", "x86_64", "universal"].contains(architecture),
              archiveSize > 0, archiveSize <= UpdateTrust.maximumArchiveSize, archiveURL == expected,
              Self.isHex(sourceCommit, count: 40), Self.isHex(archiveSHA256, count: 64) else { throw UpdateFailure.invalidManifest }
    }

    public func isNewer(than build: UInt64, version: String) throws -> Bool {
        try self.build > build && ReleaseVersion(self.version) > ReleaseVersion(version)
    }

    public func supports(architecture: String, systemVersion: String) throws -> Bool {
        guard self.architecture == architecture || self.architecture == "universal" else { return false }
        return try ReleaseVersion(minimumSystemVersion) <= ReleaseVersion(systemVersion)
    }

    private static func isHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

public struct SignedUpdateEnvelope: Codable, Sendable {
    public let schema: Int
    public let payload: String
    public let signature: String

    public init(payload: Data, signature: Data) {
        schema = 1
        self.payload = payload.base64EncodedString()
        self.signature = signature.base64EncodedString()
    }
}

public struct VerifiedUpdate: Sendable, Equatable {
    public let release: UpdateRelease
    public let envelope: Data

    public static func verify(_ data: Data, publicKey: Data? = Data(base64Encoded: UpdateTrust.publicKeyBase64)) throws -> Self {
        guard data.count <= 65_536, let publicKey, publicKey.count == 32 else { throw UpdateFailure.invalidSignature }
        do {
            let envelope = try JSONDecoder().decode(SignedUpdateEnvelope.self, from: data)
            guard envelope.schema == 1, let payload = Data(base64Encoded: envelope.payload), payload.count <= 16_384,
                  let signature = Data(base64Encoded: envelope.signature), signature.count == 64 else { throw UpdateFailure.invalidSignature }
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
            guard key.isValidSignature(signature, for: payload) else { throw UpdateFailure.invalidSignature }
            let release = try JSONDecoder().decode(UpdateRelease.self, from: payload)
            try release.validate()
            return Self(release: release, envelope: data)
        } catch let failure as UpdateFailure { throw failure }
        catch { throw UpdateFailure.invalidManifest }
    }

    public func verifyArchive(_ data: Data) throws {
        guard data.count == release.archiveSize,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == release.archiveSHA256 else {
            throw UpdateFailure.invalidArchive
        }
        try UpdateArchive.validate(data)
    }
}
