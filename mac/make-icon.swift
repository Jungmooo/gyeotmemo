// Renders the app.ico clipboard design as a macOS iconset: swift make-icon.swift <output.iconset>
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s) }
    // macOS icon grid: 824pt body centred on a 1024pt canvas.
    color(0x38634F).setFill()
    NSBezierPath(roundedRect: rect(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s).fill()
    color(0xF7F6EE).setFill()
    NSBezierPath(roundedRect: rect(262, 222, 500, 610), xRadius: 64 * s, yRadius: 64 * s).fill()
    color(0xBFD3B0).setFill()
    NSBezierPath(roundedRect: rect(392, 176, 240, 94), xRadius: 47 * s, yRadius: 47 * s).fill()
    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: 362 * s, y: (1024 - 500) * s)); tick.line(to: NSPoint(x: 462 * s, y: (1024 - 596) * s)); tick.line(to: NSPoint(x: 662 * s, y: (1024 - 392) * s))
    tick.lineWidth = 62 * s; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
    color(0x38634F).setStroke(); tick.stroke()
    color(0xCFD8C6).setFill()
    NSBezierPath(roundedRect: rect(362, 712, 300, 24), xRadius: 12 * s, yRadius: 12 * s).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
