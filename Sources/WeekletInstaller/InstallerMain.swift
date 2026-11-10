import AppKit
import Darwin
import Foundation
import WeekletCore

@main
@MainActor
enum InstallerMain {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 8 else { exit(1) }
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            guard values[arguments[index]] == nil else { exit(1) }
            values[arguments[index]] = arguments[index + 1]
        }
        guard Set(values.keys) == Set(["--parent", "--target", "--staging", "--from-build"]),
              let pid = Int32(values["--parent"]!), pid > 1, pid != getpid(),
              let oldBuild = UInt64(values["--from-build"]!) else { exit(1) }
        let target = URL(fileURLWithPath: values["--target"]!, isDirectory: true).standardizedFileURL
        let workspace = URL(fileURLWithPath: values["--staging"]!, isDirectory: true).standardizedFileURL
        let sibling = target.deletingLastPathComponent().appendingPathComponent(".Weeklet-update-\(UUID().uuidString).app")
        var swapped = false
        var parentExited = false
        do {
            try UpdateWorkspace.validate(workspace)
            guard target.lastPathComponent == "Weeklet.app",
                  let parent = NSRunningApplication(processIdentifier: pid),
                  parent.bundleIdentifier == UpdateTrust.bundleIdentifier,
                  parent.bundleURL?.standardizedFileURL.path == target.path else { throw UpdateFailure.installationFailed }
            var targetInfo = stat()
            guard lstat(target.path, &targetInfo) == 0, targetInfo.st_uid == getuid(), targetInfo.st_mode & S_IFMT == S_IFDIR,
                  FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else { throw UpdateFailure.notWritable }
            guard let envelope = try UpdateWorkspace.read("update.json", in: workspace, maximum: 65_536),
                  let archive = try UpdateWorkspace.read("archive.zip", in: workspace, maximum: UpdateTrust.maximumArchiveSize) else {
                throw UpdateFailure.invalidArchive
            }
            let update = try VerifiedUpdate.verify(envelope)
            try update.verifyArchive(archive)
            let installed = try info(target)
            guard installed.build == oldBuild, try update.release.isNewer(than: oldBuild, version: installed.version) else {
                throw UpdateFailure.invalidManifest
            }
            let system = ProcessInfo.processInfo.operatingSystemVersion
            guard try update.release.supports(architecture: UpdateTrust.architecture,
                                              systemVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)") else {
                throw UpdateFailure.unsupportedSystem
            }
            let extracted = workspace.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try run("/usr/bin/ditto", ["-x", "-k", workspace.appendingPathComponent("archive.zip").path, extracted.path])
            let candidate = extracted.appendingPathComponent("Weeklet.app", isDirectory: true)
            try checkBundle(candidate, release: update.release)
            try FileManager.default.copyItem(at: candidate, to: sibling)
            try checkBundle(sibling, release: update.release)
            try UpdateWorkspace.write(Data("ready".utf8), name: "ready", in: workspace)
            for _ in 0..<300 {
                if kill(pid, 0) != 0 && errno == ESRCH { parentExited = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard parentExited, try info(target).build == oldBuild else { throw UpdateFailure.installationFailed }
            guard renameatx_np(AT_FDCWD, sibling.path, AT_FDCWD, target.path, UInt32(RENAME_SWAP)) == 0 else {
                throw UpdateFailure.installationFailed
            }
            swapped = true
            try await reopen(target, failed: false)
            try? FileManager.default.removeItem(at: sibling)
            try? FileManager.default.removeItem(at: workspace)
        } catch {
            var rolledBack = !swapped
            if swapped {
                rolledBack = renameatx_np(AT_FDCWD, sibling.path, AT_FDCWD, target.path, UInt32(RENAME_SWAP)) == 0
            }
            if parentExited { try? await reopen(target, failed: true) }
            if rolledBack { try? FileManager.default.removeItem(at: sibling) }
            try? UpdateWorkspace.write(Data("failed".utf8), name: "failed", in: workspace)
            exit(1)
        }
    }

    private static func info(_ app: URL) throws -> (version: String, build: UInt64) {
        let file = app.appendingPathComponent("Contents/Info.plist")
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65_536 else { throw UpdateFailure.invalidArchive }
        let data = try Data(contentsOf: file)
        guard data.count <= 65_536,
              let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              value["CFBundleIdentifier"] as? String == UpdateTrust.bundleIdentifier,
              value["CFBundleExecutable"] as? String == "Weeklet",
              let version = value["CFBundleShortVersionString"] as? String,
              let text = value["CFBundleVersion"] as? String, let build = UInt64(text) else { throw UpdateFailure.invalidArchive }
        _ = try ReleaseVersion(version)
        return (version, build)
    }

    private static func checkBundle(_ app: URL, release: UpdateRelease) throws {
        let candidate = try info(app)
        guard candidate.version == release.version, candidate.build == release.build,
              let entries = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw UpdateFailure.invalidArchive
        }
        for case let file as URL in entries {
            guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw UpdateFailure.invalidArchive }
        }
        try run("/usr/bin/codesign", ["--verify", "--strict", "--deep", app.path])
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure.invalidArchive }
    }

    private static func reopen(_ target: URL, failed: Bool) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.environment = ProcessInfo.processInfo.environment.filter { ["CODEX_HOME", "CLAUDE_CONFIG_DIR"].contains($0.key) }
        config.arguments = failed ? ["--show", "--update-failed"] : ["--show"]
        config.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(at: target, configuration: config) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if app != nil { continuation.resume() }
                else { continuation.resume(throwing: UpdateFailure.installationFailed) }
            }
        }
    }
}
