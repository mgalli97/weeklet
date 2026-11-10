import WeekletCore
import AppKit

@main
@MainActor
enum WeekletMain {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--check") {
            Task {
                let service = UsageService()
                var failed = false
                for provider in Provider.allCases {
                    switch await service.fetch(provider, allowInteraction: arguments.contains("--allow-keychain")) {
                    case .success(let usage):
                        if let weekly = usage.weekly {
                            print("\(provider.name) weekly: \(weekly.usedRounded)% used, \(weekly.remainingRounded)% available; reset \(weekly.resetsAt?.ISO8601Format() ?? "unavailable")")
                        } else {
                            failed = true
                            print("\(provider.name): No weekly quota reported")
                        }
                        if let session = usage.session {
                            print("\(provider.name) 5-hour session: \(session.usedRounded)% used, \(session.remainingRounded)% available; reset \(session.resetsAt?.ISO8601Format() ?? "unavailable")")
                        }
                    case .failure(let error):
                        failed = true
                        print("\(provider.name): \(error.message). \(error.detail(for: provider))")
                    }
                }
                exit(failed ? 1 : 0)
            }
            RunLoop.main.run()
            return
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.appearance = NSAppearance(named: .darkAqua)
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            do {
                try SampleData.snapshot(to: URL(fileURLWithPath: arguments[index + 1]),
                                        errors: arguments.contains("--sample-errors"),
                                        help: arguments.contains("--sample-help"), empty: arguments.contains("--sample-empty"))
            }
            catch { fputs("Could not save sample preview.\n", stderr); exit(1) }
            return
        }
        let delegate = AppDelegate(preview: arguments.contains("--preview"), showOnLaunch: arguments.contains("--show"))
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
