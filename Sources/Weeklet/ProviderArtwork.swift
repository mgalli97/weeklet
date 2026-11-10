import AppKit
import WeekletCore

/// Provider-owned artwork is bundled locally; no logo is fetched while the app runs.
@MainActor
enum ProviderArtwork {
    private static let claude = load("ClaudeLogo", template: true)
    private static let codex = load("CodexLogo", template: false)

    static func image(for provider: Provider) -> NSImage {
        provider == .claude ? claude : codex
    }

    static func appMenuImage() -> NSImage? {
        let image = NSApp.applicationIconImage?.copy() as? NSImage
        image?.size = NSSize(width: 18, height: 18)
        return image ?? NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Weeklet")
    }

    static func activityTint(for provider: Provider) -> NSColor {
        provider == .claude
            ? NSColor(calibratedRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
            : NSColor(calibratedRed: 0.59, green: 0.77, blue: 0.72, alpha: 1)
    }

    static func menuImage(for provider: Provider, appearance: NSAppearance, activity: ProviderActivity? = nil, pulse: Bool = true) -> NSImage {
        let source = image(for: provider)
        let size = NSSize(width: 23, height: 22)
        let result = NSImage(size: size)
        appearance.performAsCurrentDrawingAppearance {
            result.lockFocus()
            let bounds = NSRect(x: 4, y: 1, width: 18, height: 18)
            source.draw(in: bounds)
            if source.isTemplate {
                NSColor(calibratedRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1).setFill()
                bounds.fill(using: .sourceIn)
            }
            if let activity, activity.isWorking {
                let text = activity.badgeText
                let diameter: CGFloat = text == nil ? 5.5 : (text!.count > 1 ? 10 : 9)
                let badge = NSRect(x: 0, y: 22 - diameter, width: diameter, height: diameter)
                NSColor(calibratedRed: 0.08, green: 0.64, blue: 0.25, alpha: pulse ? 1 : 0.45).setFill()
                NSBezierPath(ovalIn: badge).fill()
                if let text {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: text.count > 2 ? 4.5 : 6, weight: .bold),
                        .foregroundColor: NSColor.white
                    ]
                    let label = NSAttributedString(string: text, attributes: attributes)
                    let measured = label.size()
                    label.draw(at: NSPoint(x: badge.midX - measured.width / 2, y: badge.midY - measured.height / 2 + 0.25))
                }
            }
            result.unlockFocus()
        }
        return result
    }

    private static func load(_ name: String, template: Bool) -> NSImage {
        let bundle: Bundle
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Weeklet_Weeklet.bundle"),
           let embedded = Bundle(url: url) { bundle = embedded }
        else {
            #if DEBUG
            bundle = .module
            #else
            preconditionFailure("Missing embedded provider artwork")
            #endif
        }
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { preconditionFailure("Missing bundled provider artwork") }
        image.isTemplate = template
        return image
    }
}
