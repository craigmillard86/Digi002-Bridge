// Draws the app icon: a dark control surface with eight faders, eight encoder rings and
// "002", in the macOS rounded-square shape. Writes an .icns file.
// Usage: swift tools/make-icon.swift build/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.icns"

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let s = size / 1024          // everything below is laid out on a 1024 grid

    // Rounded square, inset like Apple's own icons, with a soft shadow.
    let plate = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let plateShape = NSBezierPath(roundedRect: plate, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()
    NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 1).setFill()
    plateShape.fill()
    NSShadow().set()
    NSGradient(starting: NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.35, alpha: 1),
               ending: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1))!
        .draw(in: plateShape, angle: -90)

    // Blue accent band across the top, the colour of the desk's SEL LEDs' housing.
    cg.saveGState()
    plateShape.addClip()
    NSColor(calibratedRed: 0.18, green: 0.46, blue: 0.82, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(x: plate.minX, y: plate.maxY - 150 * s, width: plate.width, height: 150 * s)).fill()
    cg.restoreGState()

    let strips = 8
    let left = plate.minX + 90 * s
    let pitch = (plate.width - 180 * s) / CGFloat(strips - 1)

    // Encoder rings: an arc of LEDs with one lit position, like the desk's rotaries.
    for i in 0..<strips {
        let centre = CGPoint(x: left + CGFloat(i) * pitch, y: plate.maxY - 215 * s)
        let ring = NSBezierPath()
        ring.appendArc(withCenter: centre, radius: 34 * s, startAngle: 225, endAngle: -45, clockwise: true)
        ring.lineWidth = 9 * s
        ring.lineCapStyle = .round
        NSColor(white: 0.08, alpha: 1).setStroke()
        ring.stroke()
        // Lit part of the ring: a different amount on each strip.
        let lit = NSBezierPath()
        let amount = CGFloat([0.35, 0.6, 0.5, 0.8, 0.45, 0.7, 0.55, 0.65][i])
        lit.appendArc(withCenter: centre, radius: 34 * s, startAngle: 225, endAngle: 225 - 270 * amount, clockwise: true)
        lit.lineWidth = 9 * s
        lit.lineCapStyle = .round
        NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.10, alpha: 1).setStroke()
        lit.stroke()
        NSColor(white: 0.22, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: centre.x - 20 * s, y: centre.y - 20 * s, width: 40 * s, height: 40 * s)).fill()
    }

    // Fader slots and caps at different heights.
    let slotBottom = plate.minY + 300 * s
    let slotHeight: CGFloat = 250 * s
    let heights: [CGFloat] = [0.55, 0.7, 0.4, 0.85, 0.6, 0.3, 0.75, 0.5]
    for i in 0..<strips {
        let x = left + CGFloat(i) * pitch
        NSColor(white: 0.06, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: x - 5 * s, y: slotBottom, width: 10 * s, height: slotHeight),
                     xRadius: 5 * s, yRadius: 5 * s).fill()
        let capY = slotBottom + slotHeight * heights[i]
        let cap = CGRect(x: x - 30 * s, y: capY - 26 * s, width: 60 * s, height: 52 * s)
        NSGradient(starting: NSColor(white: 0.85, alpha: 1), ending: NSColor(white: 0.55, alpha: 1))!
            .draw(in: NSBezierPath(roundedRect: cap, xRadius: 8 * s, yRadius: 8 * s), angle: -90)
        NSColor(white: 0.25, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: cap.minX + 6 * s, y: cap.midY - 2 * s, width: cap.width - 12 * s, height: 4 * s)).fill()
    }

    // "002" along the bottom.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    // "digi 002" as on the desk's front panel: lowercase "digi" in a lighter weight, then
    // the digits, in the rounded design of the system font, which is close to the panel.
    func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let plain = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = plain.fontDescriptor.withDesign(.rounded),
              let font = NSFont(descriptor: descriptor, size: size) else { return plain }
        return font
    }
    let text = NSMutableAttributedString()
    text.append(NSAttributedString(string: "digi ", attributes: [
        .font: rounded(150 * s, .medium),
        .foregroundColor: NSColor(white: 0.80, alpha: 1),
        .obliqueness: 0.18,        // the rounded design has no italic, so it is slanted
    ]))
    text.append(NSAttributedString(string: "002", attributes: [
        .font: rounded(150 * s, .heavy),
        .foregroundColor: NSColor(white: 0.95, alpha: 1),
        .kern: 4 * s,
        .obliqueness: 0.18,
    ]))
    text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
    let textHeight = text.size().height
    text.draw(in: CGRect(x: plate.minX, y: plate.minY + 80 * s, width: plate.width, height: textHeight))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: output).deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = draw(size: CGFloat(base * scale))
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(1) }
try? FileManager.default.removeItem(at: iconset)
print("icon: \(output)")
