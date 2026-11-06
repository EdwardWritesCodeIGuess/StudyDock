import AppKit

// Draw the app's original vector mark at each required asset size.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
func icon(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(red: 0.12, green: 0.20, blue: 0.23, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
    for (x, y, alpha) in [(220.0, 225.0, 0.35), (256.0, 270.0, 0.65), (292.0, 315.0, 1.0)] {
        NSColor(red: 0.83, green: 0.91, blue: 0.77, alpha: alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 440, height: 430), xRadius: 52, yRadius: 52).fill()
    }
    NSColor(red: 0.12, green: 0.20, blue: 0.23, alpha: 1).setStroke()
    let tick = NSBezierPath(); tick.lineWidth = 34; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
    tick.move(to: NSPoint(x: 400, y: 530)); tick.line(to: NSPoint(x: 480, y: 450)); tick.line(to: NSPoint(x: 630, y: 620)); tick.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
var images: [[String: String]] = []
try icon(1024).write(to: root.appendingPathComponent("AppIcon-1024.png"))
images.append(["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "mac-\(size)@\(scale)x.png"
        try icon(size * scale).write(to: root.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("Contents.json"))
