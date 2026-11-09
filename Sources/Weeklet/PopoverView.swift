import WeekletCore
import SwiftUI

private enum Palette {
    static let background = Color(red: 0.075, green: 0.08, blue: 0.09)
    static let foreground = Color(red: 0.92, green: 0.93, blue: 0.95)
    static let secondary = Color(red: 0.57, green: 0.60, blue: 0.65)
    static let claude = Color(red: 0.81, green: 0.60, blue: 0.47)
    static let codex = Color(red: 0.59, green: 0.77, blue: 0.72)
}

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var login: LoginItemController
    var preview = false
    var staticSnapshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Weeklet").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("WEEKLY").font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.5).foregroundStyle(Palette.secondary)
                if staticSnapshot {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                        .frame(width: 20, height: 20).foregroundStyle(Palette.secondary)
                } else { settings }
            }
            .padding(.bottom, 26)

            ForEach(Array(store.states.enumerated()), id: \.element.id) { index, state in
                UsageRow(state: state)
                if index < store.states.count - 1 { Color.white.opacity(0.07).frame(height: 1).padding(.vertical, 22) }
            }

            Color.white.opacity(0.07).frame(height: 1).padding(.top, 24).padding(.bottom, 14)
            HStack(spacing: 8) {
                Circle().fill(store.states.allSatisfy { $0.failure == nil && $0.usage != nil } ? Palette.codex : Palette.secondary)
                    .frame(width: 4, height: 4)
                Text(preview ? "Sample data" : "Menu bar shows available")
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
        .padding(22)
        .frame(width: 328)
        .foregroundStyle(Palette.foreground)
        .background(Palette.background)
        .environment(\.locale, Locale(identifier: "en_US"))
        .preferredColorScheme(.dark)
    }

    private var settings: some View {
        Menu {
            Toggle("Launch at login", isOn: Binding(get: { login.enabled || login.needsApproval }, set: { login.setEnabled($0) }))
                .disabled(!login.available || login.isChanging || preview)
            if login.needsApproval { Button("Open Login Items Settings") { login.openSettings() } }
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
    private var accent: Color { state.provider == .claude ? Palette.claude : Palette.codex }
    private var now: Date { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: state.provider == .claude ? "asterisk" : "terminal")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(accent).frame(width: 16)
                    .accessibilityHidden(true)
                Text(state.provider.name).font(.system(size: 12, weight: .medium))
                Spacer()
                if state.isLoading {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12)
                        .accessibilityLabel("Refreshing")
                }
                if let usage = state.usage {
                    Text("\(usage.usedRounded)% used").font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                } else {
                    Text("—").foregroundStyle(Palette.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    if let usage = state.usage {
                        Capsule().fill(accent.opacity(isOutdated(usage) ? 0.35 : 0.9))
                            .frame(width: geometry.size.width * usage.usedPercent / 100)
                    }
                }
            }
            .frame(height: 4)
            .accessibilityLabel("Weekly usage")
            .accessibilityValue(state.usage.map { "\($0.usedRounded) percent used" } ?? "Unavailable")

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
            } else if let usage = state.usage {
                HStack(alignment: .firstTextBaseline) {
                    Text(isOutdated(usage) ? "Awaiting refresh" : "\(usage.remainingRounded)% available")
                        .foregroundStyle(isOutdated(usage) ? Palette.secondary : accent)
                    Spacer(minLength: 8)
                    Text(resetLabel(usage.resetsAt)).foregroundStyle(Palette.secondary)
                }
                .font(.system(size: 10)).monospacedDigit()
                .help(updatedLabel(usage.fetchedAt))
            } else {
                Text(state.isLoading ? "Checking usage…" : "Waiting for refresh")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func isOutdated(_ usage: WeeklyUsage) -> Bool { state.failure != nil || !usage.isFresh(at: now) }

    private func resetLabel(_ date: Date?) -> String {
        guard let date else { return "Reset unavailable" }
        if date <= now { return "Reset pending" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d · HH:mm"
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
