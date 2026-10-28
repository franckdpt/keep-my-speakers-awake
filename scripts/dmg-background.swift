import AppKit

// A native, Retina-ready Finder background. The real app and Applications
// icons are positioned by dmg-settings.py; this only draws the instructions.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640 * scale,
        pixelsHigh: 400 * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 640, height: 400)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 640, height: 400).fill()
    func text(_ value: String, top: CGFloat, height: CGFloat, size: CGFloat,
              weight: NSFont.Weight = .regular, gray: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (value as NSString).draw(in: NSRect(x: 32, y: 400 - top - height, width: 576, height: height),
            withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor(calibratedWhite: gray, alpha: 1),
                .paragraphStyle: paragraph])
    }
    text("Keep My Speakers Awake", top: 45, height: 36, size: 26, weight: .semibold, gray: 0.12)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 287, y: 210))
    arrow.line(to: NSPoint(x: 353, y: 210))
    arrow.move(to: NSPoint(x: 341, y: 222))
    arrow.line(to: NSPoint(x: 353, y: 210))
    arrow.line(to: NSPoint(x: 341, y: 198))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedWhite: 0.64, alpha: 1).setStroke()
    arrow.stroke()
    text("Drag the app to Applications", top: 314, height: 25, size: 16, gray: 0.30)
    text("Glissez l’app dans Applications", top: 341, height: 22, size: 14, gray: 0.43)
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}
