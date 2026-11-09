import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: factor, y: factor)
        NSColor(calibratedRed: 0.075, green: 0.08, blue: 0.09, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210).fill()
        let colors = [NSColor(calibratedRed: 0.81, green: 0.60, blue: 0.47, alpha: 1),
                      NSColor(calibratedRed: 0.59, green: 0.77, blue: 0.72, alpha: 1)]
        for (index, color) in colors.enumerated() {
            let x = CGFloat(290 + index * 300)
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 275, width: 140, height: 474), xRadius: 70, yRadius: 70).fill()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 275, width: 140, height: index == 0 ? 300 : 400), xRadius: 70, yRadius: 70).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
