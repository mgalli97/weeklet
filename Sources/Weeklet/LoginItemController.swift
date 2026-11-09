import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var isChanging = false
    @Published private(set) var errorMessage: String?
    var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    init() { refresh() }

    func refresh() {
        enabled = available && SMAppService.mainApp.status == .enabled
        needsApproval = available && SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        guard available, !isChanging else { return }
        isChanging = true
        errorMessage = nil
        Task {
            do {
                if value { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
            } catch {
                errorMessage = "Could not change launch at login."
            }
            refresh()
            isChanging = false
        }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
