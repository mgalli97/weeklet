import AppKit
import Combine
import Foundation
import WeekletCore

@MainActor
final class UpdateController: ObservableObject {
    enum State: Equatable { case idle, checking, downloading, installing, message(String) }
    @Published private(set) var state: State = .idle
    @Published private(set) var available: VerifiedUpdate?
    private let service = GitHubUpdates()
    private let preview: Bool
    private var lastCheck: Date?
    private var manualCheck = false
    private var task: Task<Void, Never>?
    private var installer: Process?
    let currentVersion: String
    private let currentBuild: UInt64

    init(preview: Bool = false, previousInstallFailed: Bool = false) {
        self.preview = preview
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        currentBuild = UInt64(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        if previousInstallFailed { state = .message(UpdateFailure.installationFailed.message) }
    }

    var busy: Bool { state == .checking || state == .downloading || state == .installing }
    var banner: String? {
        switch state {
        case .checking: return manualCheck ? "Checking for updates…" : nil
        case .downloading: return "Downloading update…"
        case .installing: return "Preparing to restart…"
        case .message(let message): return message
        case .idle: return available.map { "Version \($0.release.version) available" }
        }
    }

    func check(manual: Bool = false) {
        guard !preview, !busy else { return }
        if !manual, lastCheck.map({ Date().timeIntervalSince($0) < 3600 }) == true { return }
        lastCheck = Date()
        manualCheck = manual
        state = .checking
        task = Task { [weak self, service] in
            do {
                let update = try await service.check()
                guard let self, !Task.isCancelled else { return }
                guard try update.release.isNewer(than: self.currentBuild, version: self.currentVersion) else {
                    self.available = nil
                    self.state = manual ? .message("You're up to date") : .idle
                    return
                }
                let system = ProcessInfo.processInfo.operatingSystemVersion
                guard update.release.architecture == UpdateTrust.architecture || update.release.architecture == "universal" else {
                    throw UpdateFailure.unsupportedArchitecture
                }
                guard try update.release.supports(architecture: UpdateTrust.architecture,
                                                  systemVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)") else {
                    throw UpdateFailure.unsupportedSystem
                }
                self.available = update
                self.state = .idle
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.state = manual ? .message((error as? UpdateFailure)?.message ?? UpdateFailure.network.message) : .idle
            }
        }
    }

    func dismissNotice() {
        if case .message = state { state = .idle }
    }

    func install() {
        guard !preview, !busy, let available else { return }
        state = .downloading
        task = Task { [weak self, service] in
            var workspace: URL?
            do {
                let folder = try await service.download(available)
                workspace = folder
                guard let self, !Task.isCancelled else { throw UpdateFailure.installationFailed }
                self.state = .installing
                let app = Bundle.main.bundleURL
                guard app.lastPathComponent == "Weeklet.app" else { throw UpdateFailure.installationFailed }
                let process = Process()
                process.executableURL = app.appendingPathComponent("Contents/MacOS/WeekletInstaller")
                process.arguments = ["--parent", String(ProcessInfo.processInfo.processIdentifier), "--target", app.path,
                                     "--staging", folder.path, "--from-build", String(self.currentBuild)]
                process.environment = UpdateEnvironment.installer(from: ProcessInfo.processInfo.environment,
                                                                  temporaryDirectory: FileManager.default.temporaryDirectory)
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                self.installer = process
                for _ in 0..<600 {
                    if try UpdateWorkspace.read("failed", in: folder, maximum: 64) != nil { throw UpdateFailure.installationFailed }
                    if try UpdateWorkspace.read("ready", in: folder, maximum: 64) == Data("ready".utf8) {
                        NSApp.terminate(nil)
                        return
                    }
                    guard process.isRunning else { throw UpdateFailure.installationFailed }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw UpdateFailure.installationFailed
            } catch {
                guard let self else { return }
                if self.installer?.isRunning == true { self.installer?.terminate() }
                self.installer = nil
                if let workspace { try? FileManager.default.removeItem(at: workspace) }
                self.state = .message((error as? UpdateFailure)?.message ?? UpdateFailure.installationFailed.message)
            }
        }
    }
}
