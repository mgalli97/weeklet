import WeekletCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let store: UsageStore
    private let login = LoginItemController()
    private var observation: AnyCancellable?
    private var wakeObservation: NSObjectProtocol?
    private let preview: Bool

    init(preview: Bool) {
        self.preview = preview
        store = preview ? SampleData.store() : UsageStore()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store, login: login, preview: preview))
        observation = store.$states.sink { [weak self] states in
            guard let self else { return }
            // Published values arrive before the stored property changes.
            self.updateTitle(states)
        }
        wakeObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.store.refreshIfDue() }
        }
        if !preview { store.start() }
    }

    private func updateTitle(_ states: [ProviderState]) {
        let title = states.map { "\($0.provider.shortName) \($0.menuValue(at: Date()))" }.joined(separator: "  ·  ")
        statusItem?.button?.title = title
        statusItem?.button?.toolTip = "Weekly available · C: Claude Code · X: ChatGPT Codex" + (preview ? " · Sample data" : "")
        statusItem?.button?.setAccessibilityLabel("Weeklet. " + states.map {
            "\($0.provider.name): \($0.menuValue(at: Date())) available"
        }.joined(separator: ". "))
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        login.refresh()
        updateTitle(store.states)
        if !preview { store.refreshIfDue() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        if let wakeObservation { NSWorkspace.shared.notificationCenter.removeObserver(wakeObservation) }
    }
}

@MainActor
enum SampleData {
    static func store(errors: Bool = false) -> UsageStore {
        let now = Date()
        let claude = try! WeeklyUsage(usedPercent: 37, resetsAt: now.addingTimeInterval(172_800), fetchedAt: now)
        let codex = try! WeeklyUsage(usedPercent: 68, resetsAt: now.addingTimeInterval(345_600), fetchedAt: now)
        return UsageStore(states: [
            errors ? ProviderState(provider: .claude, failure: .expiredSession) : ProviderState(provider: .claude, usage: claude),
            ProviderState(provider: .codex, usage: codex)
        ])
    }

    static func snapshot(to url: URL, errors: Bool = false) throws {
        // ImageRenderer cannot render AppKit's menu control. Render its identical label only.
        let view = PopoverView(store: store(errors: errors), login: LoginItemController(), preview: true, staticSnapshot: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
