import AppKit

// Compose lossless App Store screenshots around the app's own no-audio preview renders.
// No UI is redrawn, invented or altered here.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("output/app-store/screenshots")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let app = root.appendingPathComponent("output/native-app-store/Keep My Speakers Awake.app/Contents/MacOS/KMSA")
let french = [
    ("01", "Vos enceintes,\nprêtes à jouer.", "Des réveils basse fréquence automatiques.\nUn petit utilitaire dans la barre des menus.", ["--automatic"]),
    ("02", "Le contrôle\nen un clic.", "Réglage du niveau, test manuel\net démarrage à la connexion en option.", [String]()),
    ("03", "Des protections\nau quotidien.", "Microphone actif : signaux bloqués.\nLe mode intelligent s’adapte à l’activité du Mac.", ["--help-content"]),
]
let english = [
    ("01", "Keep your\nspeakers ready.", "Automatic low-frequency wake-up signals.\nA small utility in your menu bar.", ["--automatic"]),
    ("02", "One click.\nYou’re in control.", "Adjust the signal, run a manual test\nand choose whether to open at login.", [String]()),
    ("03", "Everyday\nprotections.", "Microphone active? Signals stay paused.\nSmart Mode follows your Mac’s activity.", ["--help-content"]),
]
func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = size * 0.12
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: style]
    let string = NSAttributedString(string: value, attributes: attributes)
    let bounds = string.boundingRect(with: NSSize(width: width, height: 1500), options: [.usesLineFragmentOrigin, .usesFontLeading])
    string.draw(with: NSRect(x: x, y: y - ceil(bounds.height), width: width, height: ceil(bounds.height) + 3),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
}
for (locale, scenes) in [("fr-FR", french), ("en-US", english)] {
    for (number, title, subtitle, flags) in scenes {
        let native = folder.appendingPathComponent("native-\(locale)-\(number).png")
        let task = Process()
        task.executableURL = app
        task.arguments = ["--preview", "-", "-AppleLanguages", locale == "fr-FR" ? "(fr)" : "(en)", "-AppleInterfaceStyle", "Light"] + flags
        let pipe = Pipe(); task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, let panel = NSImage(data: data) else { fatalError("Native preview failed") }
        try data.write(to: native)
        let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2880, pixelsHigh: 1800,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: canvas)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 2880, height: 1800).fill()
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            text("KMSA  /  Keep My Speakers Awake", x: 150, y: 1645, width: 1600, size: 34, weight: .medium,
                 color: NSColor(calibratedWhite: 0.35, alpha: 1))
            text(title, x: 150, y: 1350, width: 1370, size: 106, weight: .bold,
                 color: NSColor(calibratedWhite: 0.08, alpha: 1))
            text(subtitle, x: 155, y: 980, width: 1320, size: 42,
                 color: NSColor(calibratedWhite: 0.34, alpha: 1))
            text("Apple Silicon  ·  macOS 14.2+", x: 155, y: 175, width: 1300, size: 31,
                 color: NSColor(calibratedWhite: 0.38, alpha: 1))
            let ratio = min(960 / panel.size.width, 1300 / panel.size.height)
            let size = NSSize(width: panel.size.width * ratio, height: panel.size.height * ratio)
            let frame = NSRect(x: 1695 + (960 - size.width) / 2, y: (1800 - size.height) / 2,
                               width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
            shadow.shadowBlurRadius = 45; shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.set()
            NSColor.white.setFill(); NSBezierPath(roundedRect: frame, xRadius: 28, yRadius: 28).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 28, yRadius: 28).addClip()
            panel.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        try canvas.representation(using: .jpeg, properties: [.compressionFactor: 0.96])!.write(to: folder.appendingPathComponent("\(locale)-\(number).jpg"))
    }
}
print("Exported six 2880 × 1800 JPEG screenshots from the native App Store build. No audio played.")
