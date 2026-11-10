import WeekletCore
import SwiftUI

private enum Palette {
    static let background = Color(red: 0.075, green: 0.08, blue: 0.09)
    static let foreground = Color(red: 0.92, green: 0.93, blue: 0.95)
    static let secondary = Color(red: 0.57, green: 0.60, blue: 0.65)
    static let claude = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
    static let codex = Color(red: 0.59, green: 0.77, blue: 0.72)
}

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var login: LoginItemController
    @ObservedObject var activity: ActivityStore
    @ObservedObject var updates: UpdateController
    var preview = false
    var staticSnapshot = false
    var helpPreview = false
    var onContentChange: () -> Void = {}
    @State private var showingHelp = false
    private var visibleStates: [ProviderState] { store.visibleStates }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if showingHelp || helpPreview { helpContent }
                else { usageContent }
            }
            Text("v\(updates.currentVersion)")
                .font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(Palette.secondary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 8)
                .accessibilityLabel("Weeklet version \(updates.currentVersion)")
        }
        .padding(22)
        .frame(width: 328)
        .foregroundStyle(Palette.foreground)
        .background(Palette.background)
        .environment(\.locale, Locale(identifier: "en_US"))
        .preferredColorScheme(.dark)
        .onChange(of: showingHelp) { _, _ in onContentChange() }
    }

    private var usageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Weeklet").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("USAGE").font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.5).foregroundStyle(Palette.secondary)
                if staticSnapshot {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                        .frame(width: 20, height: 20).foregroundStyle(Palette.secondary)
                } else { settings }
            }
            .padding(.bottom, 26)

            if visibleStates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.isRefreshing ? "Checking sign-ins…" : "No providers connected")
                        .font(.system(size: 12, weight: .medium))
                    Text("Open Help to set up Claude Code or Codex.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Help") { showingHelp = true }
                        .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                        .padding(.top, 2)
                }
            }

            ForEach(Array(visibleStates.enumerated()), id: \.element.id) { index, state in
                UsageRow(state: state, activity: activity.states.first { $0.provider == state.provider }, pulse: activity.pulse)
                if index < visibleStates.count - 1 { Color.white.opacity(0.07).frame(height: 1).padding(.vertical, 22) }
            }

            if let banner = updates.banner {
                Color.white.opacity(0.07).frame(height: 1).padding(.top, 20).padding(.bottom, 12)
                HStack(spacing: 10) {
                    Text(banner).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !updates.busy {
                        Button(updates.available == nil ? "Check" : "Update") {
                            if updates.available != nil { updates.install() }
                            else { updates.check(manual: true) }
                        }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    }
                }
            }
            Color.white.opacity(0.07).frame(height: 1).padding(.top, 24).padding(.bottom, 14)
            HStack(spacing: 8) {
                Circle().fill(!visibleStates.isEmpty && visibleStates.allSatisfy { $0.failure == nil && $0.usage != nil } ? Palette.codex : Palette.secondary)
                    .frame(width: 4, height: 4)
                Text(preview ? "Sample data" : visibleStates.isEmpty ? "Sign in, then refresh" : "Menu bar shows available")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Button { store.refresh(manual: true) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondary)
                .disabled(store.isRefreshing || preview)
                .opacity(store.isRefreshing ? 0.35 : 1)
                .help(store.isRefreshing ? "Refreshing…" : "Refresh · every 5 minutes")
                .accessibilityLabel(store.isRefreshing ? "Refreshing" : "Refresh usage")
                .keyboardShortcut("r", modifiers: .command)
            }
            if login.needsApproval || login.errorMessage != nil {
                Button(login.errorMessage ?? "Allow launch at login in Settings") { login.openSettings() }
                    .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.secondary).padding(.top, 8)
            }
        }
    }

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Help").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { showingHelp = false }
                    .font(.system(size: 11)).buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            Text("Sign in with your subscription from Terminal.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(store.states) { state in
                helpProvider(state)
            }
            Text("Missing or expired? Sign in again, then refresh.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    showingHelp = false
                    store.refresh(manual: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(store.isRefreshing || preview)
                Spacer()
                if preview {
                    Text("Sample data").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    private func helpProvider(_ state: ProviderState) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(nsImage: ProviderArtwork.image(for: state.provider))
                    .resizable().renderingMode(state.provider == .claude ? .template : .original)
                    .scaledToFit().frame(width: 18, height: 18)
                    .foregroundStyle(state.provider == .claude ? Palette.claude : Palette.foreground)
                    .accessibilityHidden(true)
                Text(state.provider.name).font(.system(size: 12, weight: .medium))
            }
            if let failure = state.failure {
                Text(failure == .credentialAccess || failure == .insecureCredentials ? failure.detail(for: state.provider) : failure.message)
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(state.provider.signInCommand).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.provider.signInCommand, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain).help("Copy command")
                .accessibilityLabel("Copy \(state.provider.name) sign-in command")
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var settings: some View {
        Menu {
            Toggle("Launch at login", isOn: Binding(get: { login.enabled || login.needsApproval }, set: { login.setEnabled($0) }))
                .disabled(!login.available || login.isChanging || preview)
            if login.needsApproval { Button("Open Login Items Settings") { login.openSettings() } }
            Divider()
            Button("Check for Updates") { updates.check(manual: true) }.disabled(updates.busy || preview)
            Text("Weeklet \(updates.currentVersion)")
            Divider()
            Button("Help") { showingHelp = true }
            Divider()
            Button("Quit Weeklet") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Palette.secondary)
        .help("Options")
        .accessibilityLabel("Options")
    }
}

private struct UsageRow: View {
    let state: ProviderState
    let activity: ProviderActivity?
    let pulse: Bool
    private var accent: Color { state.provider == .claude ? Palette.claude : Palette.codex }
    private var now: Date { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: ProviderArtwork.image(for: state.provider))
                    .resizable()
                    .renderingMode(state.provider == .claude ? .template : .original)
                    .scaledToFit()
                    .foregroundStyle(state.provider == .claude ? Palette.claude : Palette.foreground)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(state.provider.name).font(.system(size: 12, weight: .medium))
                Spacer()
                if state.isLoading {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12)
                        .accessibilityLabel("Refreshing")
                }
                if let usage = state.usage?.weekly {
                    Text("\(usage.usedRounded)% used · weekly").font(.system(size: 10)).monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                } else {
                    Text("—").foregroundStyle(Palette.secondary)
                }
            }

            if let activity, activity.isWorking {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 4, height: 4).opacity(pulse ? 1 : 0.35)
                            .animation(.easeInOut(duration: 0.7), value: pulse)
                        Text(activity.displayTitle).font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    if activity.activeCount > 1 {
                        ForEach(Array(activity.chats.prefix(3))) { chat in
                            Text(chat.title ?? "Untitled chat").font(.system(size: 9))
                                .foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                        }
                        if activity.activeCount > 3 {
                            Text("+\(activity.activeCount - 3) more").font(.system(size: 8)).foregroundStyle(.white)
                        }
                    }
                }
                .padding(.leading, 28)
                .help(activity.activeCount > 1 ? "\(activity.activeCount) chats working" : "Working · " + activity.displayTitle)
                .accessibilityLabel(activity.activeCount > 1 ? "\(activity.activeCount) chats working" : "Working on " + activity.displayTitle)
            }

            quotaBar(state.usage?.weekly, label: "Weekly usage")

            if let failure = state.failure {
                HStack(alignment: .firstTextBaseline) {
                    Text(failure.message).font(.system(size: 11))
                    Spacer(minLength: 8)
                    if state.usage != nil { Text("Last known").font(.system(size: 10)) }
                }
                .foregroundStyle(Palette.secondary)
                .help(failure.detail(for: state.provider))
                if failure == .notSignedIn || failure == .expiredSession || failure == .unsupportedAuth || failure == .credentialAccess {
                    Text(failure.detail(for: state.provider)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .rateLimited(let until) = failure {
                    Text("Try after \(Self.time(until))").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            } else if let usage = state.usage?.weekly {
                HStack(alignment: .firstTextBaseline) {
                    Text(isOutdated(usage) ? "Awaiting refresh" : "\(usage.remainingRounded)% available")
                        .foregroundStyle(isOutdated(usage) ? Palette.secondary : accent)
                    Spacer(minLength: 8)
                    Text(resetLabel(usage.resetsAt)).foregroundStyle(Palette.secondary)
                }
                .font(.system(size: 10)).monospacedDigit()
                .help(updatedLabel(usage.fetchedAt))
            } else {
                Text(state.isLoading ? "Checking usage…" : state.usage == nil ? "Waiting for refresh" : "No weekly quota reported")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }

            if state.provider == .claude, let snapshot = state.usage {
                if let session = snapshot.session {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("5-hour session")
                            Spacer()
                            Text("\(session.usedRounded)% used").monospacedDigit()
                        }
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        quotaBar(session, label: "5-hour session usage")
                        HStack {
                            Text(isOutdated(session) ? "Awaiting refresh" : "\(session.remainingRounded)% available")
                                .foregroundStyle(isOutdated(session) ? Palette.secondary : accent)
                            Spacer()
                            Text(resetLabel(session.resetsAt, session: true)).foregroundStyle(Palette.secondary)
                        }
                        .font(.system(size: 10)).monospacedDigit()
                        .help(updatedLabel(session.fetchedAt))
                    }
                    .padding(.top, 6)
                } else {
                    Text("5-hour session unavailable").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func isOutdated(_ usage: QuotaUsage) -> Bool { state.failure != nil || !usage.isFresh(at: now) }

    private func quotaBar(_ usage: QuotaUsage?, label: String) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                if let usage {
                    Capsule().fill(accent.opacity(isOutdated(usage) ? 0.35 : 0.9))
                        .frame(width: geometry.size.width * usage.usedPercent / 100)
                }
            }
        }
        .frame(height: 4)
        .accessibilityLabel(label)
        .accessibilityValue(usage.map { "\($0.usedRounded) percent used" } ?? "Unavailable")
    }

    private func resetLabel(_ date: Date?, session: Bool = false) -> String {
        guard let date else { return "Reset unavailable" }
        if date <= now { return "Reset pending" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = session ? "HH:mm" : "EEE, MMM d · HH:mm"
        return "Resets " + formatter.string(from: date)
    }

    private func updatedLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated " + formatter.string(from: date) + " · Local time"
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
