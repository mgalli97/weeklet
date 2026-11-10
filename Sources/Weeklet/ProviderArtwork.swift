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

    static func menuImage(for provider: Provider, appearance: NSAppearance) -> NSImage {
        let source = image(for: provider)
        let size = NSSize(width: 18, height: 18)
        let result = NSImage(size: size)
        appearance.performAsCurrentDrawingAppearance {
            result.lockFocus()
            let bounds = NSRect(origin: .zero, size: size)
            source.draw(in: bounds)
            if source.isTemplate {
                NSColor(calibratedRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1).setFill()
                bounds.fill(using: .sourceIn)
            }
            result.unlockFocus()
        }
        return result
    }

    private static func load(_ name: String, template: Bool) -> NSImage {
        let bundle: Bundle
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Weeklet_Weeklet.bundle"),
           let embedded = Bundle(url: url) { bundle = embedded }
        else { bundle = .module }
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { preconditionFailure("Missing bundled provider artwork") }
        image.isTemplate = template
        return image
    }
}
