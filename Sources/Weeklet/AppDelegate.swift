import WeekletCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let store: UsageStore
    private let activity: ActivityStore
    private let login = LoginItemController()
    private let menuFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private var observation: AnyCancellable?
    private var activityObservation: AnyCancellable?
    private var countdownTimer: Timer?
    private var lastActivityStates: [ProviderActivity] = []
    private var wakeObservation: NSObjectProtocol?
    private var popoverObservations: [NSObjectProtocol] = []
    private let preview: Bool
    private let showOnLaunch: Bool

    init(preview: Bool, showOnLaunch: Bool = false) {
        self.preview = preview
        self.showOnLaunch = showOnLaunch
        store = preview ? SampleData.store() : UsageStore()
        activity = preview ? SampleData.activity() : ActivityStore()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.font = menuFont
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        let root = PopoverView(store: store, login: login, activity: activity, preview: preview, onContentChange: { [weak self] in
            Task { @MainActor in self?.updatePopoverLayout() }
        })
        let hosting = NSHostingController(rootView: root.fixedSize())
        hosting.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        hosting.safeAreaRegions = []
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        observation = store.$states.sink { [weak self] states in
            guard let self else { return }
            // Published values arrive before the stored property changes.
            self.updateTitle(states)
            Task { @MainActor in self.updatePopoverLayout() }
        }
        activityObservation = Publishers.CombineLatest3(activity.$states, activity.$pulse, activity.$verb).sink { [weak self] states, pulse, verb in
            guard let self else { return }
            self.updateTitle(self.store.states, activities: states, pulse: pulse, verb: verb)
            if states != self.lastActivityStates {
                self.lastActivityStates = states
                Task { @MainActor in self.updatePopoverLayout() }
            }
        }
        wakeObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateTitle(self.store.states)
                self.store.refreshIfDue()
            }
        }
        if !preview {
            // An explicitly opened foreground check may show macOS's Keychain dialog.
            if showOnLaunch { store.refresh(manual: true) }
            store.start()
            activity.start()
        }
        if showOnLaunch { Task { @MainActor in self.showPopover() } }
    }

    private func updateTitle(_ states: [ProviderState], activities: [ProviderActivity]? = nil, pulse: Bool? = nil, verb: ActivityVerb? = nil) {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let visible = states.filter(\.isVisible)
        let visibleProviders = Set(visible.map(\.provider))
        button.image = visible.isEmpty ? ProviderArtwork.appMenuImage() : nil
        let title = NSMutableAttributedString(string: "")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: menuFont,
            .foregroundColor: NSColor.labelColor
        ]
        for (index, state) in visible.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: "  |  ", attributes: attributes)) }
            let logo = NSTextAttachment()
            logo.image = ProviderArtwork.menuImage(for: state.provider, appearance: button.effectiveAppearance)
            logo.bounds = NSRect(x: 0, y: -4, width: 18, height: 18)
            title.append(NSAttributedString(attachment: logo))
            title.append(NSAttributedString(string: " \(state.menuSummary(at: now))", attributes: attributes))
            if let working = (activities ?? activity.states).first(where: { $0.provider == state.provider && $0.isWorking }) {
                title.append(NSAttributedString(string: "  • ", attributes: [
                    .font: menuFont,
                    .foregroundColor: ProviderArtwork.activityTint(for: state.provider).withAlphaComponent((pulse ?? activity.pulse) ? 1 : 0.35)
                ]))
                let word = verb ?? activity.verb
                let providerWord = state.provider == .codex ? word.next.next : word
                title.append(NSAttributedString(string: working.menuLabel(verb: providerWord), attributes: [
                    .font: menuFont, .foregroundColor: NSColor.white
                ]))
            }
        }
        button.attributedTitle = title
        let working = (activities ?? activity.states).filter { $0.isWorking && visibleProviders.contains($0.provider) }.map { state in
            let names = state.chats.prefix(3).map { $0.title ?? "Untitled chat" }.joined(separator: ", ")
            return state.activeCount > 1 ? "\(state.provider.name): \(state.displayTitle) · \(names)" : "\(state.provider.name): \(state.displayTitle)"
        }
        let hint = visible.isEmpty ? "Weeklet · Open Options → Help to connect a provider" : "Available · h: 5-hour session · w: weekly · lft: until reset"
        button.toolTip = ([hint] + working).joined(separator: "\n") + (preview ? " · Sample data" : "")
        let summary = visible.isEmpty ? "No providers connected. Open Options, then Help." : visible.map {
            "\($0.provider.name): \($0.menuSummary(at: now).replacingOccurrences(of: " lft", with: " left")) available"
        }.joined(separator: ". ")
        button.setAccessibilityLabel("Weeklet. " + summary + (working.isEmpty ? "" : ". Working: " + working.joined(separator: ". ")))
        updateCountdownTimer(visible, at: now)
    }

    private func updateCountdownTimer(_ states: [ProviderState], at date: Date) {
        let needed = !preview && states.contains {
            $0.menuResetCountdown(at: date) != nil ||
                ($0.provider == .claude && $0.menuResetCountdown(at: date, period: .session) != nil)
        }
        guard needed else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            return
        }
        guard countdownTimer == nil else { return }
        // Reformat locally while a countdown is visible; provider polling remains every five minutes.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateTitle(self.store.states)
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        login.refresh()
        updateTitle(store.states)
        if !preview { store.refreshIfDue() }
        button.window?.contentView?.layoutSubtreeIfNeeded()
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = view.fittingSize
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        positionPopover()
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidShow(_ notification: Notification) {
        guard let window = popover.contentViewController?.view.window else { return }
        popoverObservations.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.positionPopover() }
        })
        positionPopover()
    }

    func popoverDidClose(_ notification: Notification) {
        popoverObservations.forEach(NotificationCenter.default.removeObserver)
        popoverObservations.removeAll()
    }

    private func updatePopoverLayout() {
        guard popover.isShown, let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        if size.width > 0, size.height > 0, popover.contentSize != size { popover.contentSize = size }
        positionPopover()
    }

    private func positionPopover() {
        guard popover.isShown, let button = statusItem?.button, let statusWindow = button.window,
              let window = popover.contentViewController?.view.window, let screen = statusWindow.screen else { return }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let top = min(anchor.minY - 8, visible.maxY)
        let origin = NSPoint(x: max(visible.minX, min(window.frame.minX, visible.maxX - window.frame.width)),
                             y: max(visible.minY, top - window.frame.height))
        if abs(window.frame.minX - origin.x) > 0.5 || abs(window.frame.minY - origin.y) > 0.5 {
            window.setFrameOrigin(origin)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        countdownTimer?.invalidate()
        store.stop()
        activity.stop()
        popoverObservations.forEach(NotificationCenter.default.removeObserver)
        if let wakeObservation { NSWorkspace.shared.notificationCenter.removeObserver(wakeObservation) }
    }
}

@MainActor
enum SampleData {
    static func activity() -> ActivityStore {
        ActivityStore(states: [ProviderActivity(provider: .claude), ProviderActivity(provider: .codex, chats: [
            WorkingChat(id: "sample-build", title: "Build interface"),
            WorkingChat(id: "sample-review", title: "Review changes")
        ])])
    }

    static func store(errors: Bool = false, empty: Bool = false) -> UsageStore {
        if empty { return UsageStore(states: Provider.allCases.map { ProviderState(provider: $0, failure: .notSignedIn) }) }
        let now = Date()
        let claude = try! QuotaUsage(usedPercent: 37, resetsAt: now.addingTimeInterval(172_800), fetchedAt: now)
        let session = try! QuotaUsage(usedPercent: 21, resetsAt: now.addingTimeInterval(10_800), fetchedAt: now)
        let codex = try! QuotaUsage(usedPercent: 68, resetsAt: now.addingTimeInterval(345_600), fetchedAt: now)
        return UsageStore(states: [
            errors ? ProviderState(provider: .claude, failure: .expiredSession) : ProviderState(provider: .claude, usage: UsageSnapshot(weekly: claude, session: session)),
            ProviderState(provider: .codex, usage: UsageSnapshot(weekly: codex))
        ])
    }

    static func snapshot(to url: URL, errors: Bool = false, help: Bool = false, empty: Bool = false) throws {
        // ImageRenderer cannot render AppKit's menu control. Render its identical label only.
        let view = PopoverView(store: store(errors: errors, empty: empty), login: LoginItemController(), activity: activity(), preview: true, staticSnapshot: true, helpPreview: help)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
