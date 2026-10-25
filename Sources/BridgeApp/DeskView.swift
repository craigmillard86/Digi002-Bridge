import AppKit
import BridgeCore
import Digi00x

/// A picture of the desk as the bridge last drew it: eight strips with fader, ring, name
/// and LEDs, the two right-hand displays, and the LED buttons that have a state. Fed by
/// `BridgeService.onSurface`, so it shows what the bridge sends whether or not a desk is
/// plugged in.
final class DeskView: NSView {
    private var faders = [Int](repeating: 0, count: 8)
    private var rings = [Ring](repeating: .off, count: 8)
    private var displays = [String](repeating: "", count: 10)
    private var inverse = [Bool](repeating: false, count: 10)
    private var leds: [Button: Bool] = [:]
    /// The photo and layout to draw on, or nil for the schematic.
    var picture: (image: NSImage, layout: DeskLayout)? {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// Height for the current width: the photo's own shape, or the schematic's.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard let picture else { return Self.schematicHeight }
        let size = picture.image.size
        return min(width * size.height / size.width, 480)
    }

    static let schematicHeight: CGFloat = 340
    override var intrinsicContentSize: NSSize { NSSize(width: 548, height: Self.schematicHeight) }
    override var isFlipped: Bool { true }

    // Colours of the real desk: charcoal body, silver panel, amber displays.
    private static let body = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
    private static let panel = NSColor(calibratedRed: 0.78, green: 0.79, blue: 0.81, alpha: 1)
    private static let buttonFace = NSColor(calibratedRed: 0.30, green: 0.31, blue: 0.34, alpha: 1)
    private static let amber = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.10, alpha: 1)
    private static let ledOff = NSColor(calibratedWhite: 0.22, alpha: 1)

    func apply(_ commands: [SurfaceCommand]) {
        for command in commands {
            switch command {
            case let .fader(channel, position):
                if channel < 8 { faders[channel] = position }
            case let .led(button, on):
                leds[button] = on
            case let .ring(channel, ring):
                if channel < 8 { rings[channel] = ring }
            case let .display(strip, text, isInverse):
                if strip < 10 { displays[strip] = text; inverse[strip] = isInverse }
            }
        }
        needsDisplay = true
    }

    func reset() {
        faders = [Int](repeating: 0, count: 8)
        rings = [Ring](repeating: .off, count: 8)
        displays = [String](repeating: "", count: 10)
        inverse = [Bool](repeating: false, count: 10)
        leds = [:]
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let picture {
            drawOverlay(picture.image, picture.layout)
            return
        }
        drawSchematic()
    }

    // MARK: Schematic

    /// The desk from above, in the proportions of the real one: the dark top band with
    /// the mic gain knobs, the displays and the monitor knobs; the silver panel with the
    /// encoders, the left column, the strips and the right-hand button block.
    private func drawSchematic() {
        // Body: charcoal, big corner radius, a little lighter towards the back and a broad
        // front lip (the palm rest) along the bottom.
        let bodyPath = NSBezierPath(roundedRect: bounds, xRadius: 24, yRadius: 24)
        NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.27, alpha: 1),
                   ending: Self.body)?.draw(in: bodyPath, angle: -90)
        let lip = NSBezierPath()
        lip.move(to: NSPoint(x: 0, y: bounds.height - 24))
        lip.curve(to: NSPoint(x: bounds.width, y: bounds.height - 24),
                  controlPoint1: NSPoint(x: bounds.width * 0.3, y: bounds.height - 34),
                  controlPoint2: NSPoint(x: bounds.width * 0.7, y: bounds.height - 34))
        lip.line(to: NSPoint(x: bounds.width, y: bounds.height))
        lip.line(to: NSPoint(x: 0, y: bounds.height))
        lip.close()
        NSGraphicsContext.saveGraphicsState()
        bodyPath.addClip()
        NSGradient(starting: NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.31, alpha: 1),
                   ending: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1))?.draw(in: lip, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // Silver panel: an L shape, tall under the strips and shorter under the right-hand
        // block, with a brushed gradient. Its top edge runs just above the SEL buttons.
        let panelTop: CGFloat = 108, panelBottom: CGFloat = bounds.height - 26
        let panel = NSBezierPath()
        let r: CGFloat = 10
        let l: CGFloat = 10, stripRight: CGFloat = 400, rightTop: CGFloat = 165, right: CGFloat = bounds.width - 10
        panel.move(to: NSPoint(x: l + r, y: panelTop))
        panel.line(to: NSPoint(x: stripRight - r, y: panelTop))
        panel.appendArc(withCenter: NSPoint(x: stripRight - r, y: panelTop + r), radius: r, startAngle: 270, endAngle: 360)
        panel.line(to: NSPoint(x: stripRight, y: rightTop - r))
        panel.appendArc(withCenter: NSPoint(x: stripRight + r, y: rightTop - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
        panel.line(to: NSPoint(x: right - r, y: rightTop))
        panel.appendArc(withCenter: NSPoint(x: right - r, y: rightTop + r), radius: r, startAngle: 270, endAngle: 360)
        panel.line(to: NSPoint(x: right, y: panelBottom - r))
        panel.appendArc(withCenter: NSPoint(x: right - r, y: panelBottom - r), radius: r, startAngle: 0, endAngle: 90)
        panel.line(to: NSPoint(x: l + r, y: panelBottom))
        panel.appendArc(withCenter: NSPoint(x: l + r, y: panelBottom - r), radius: r, startAngle: 90, endAngle: 180)
        panel.line(to: NSPoint(x: l, y: panelTop + r))
        panel.appendArc(withCenter: NSPoint(x: l + r, y: panelTop + r), radius: r, startAngle: 180, endAngle: 270)
        panel.close()
        NSGradient(starting: NSColor(calibratedRed: 0.86, green: 0.87, blue: 0.88, alpha: 1),
                   ending: NSColor(calibratedRed: 0.72, green: 0.73, blue: 0.76, alpha: 1))?.draw(in: panel, angle: 90)
        NSColor(calibratedWhite: 1, alpha: 0.5).setStroke()
        panel.lineWidth = 0.5
        panel.stroke()

        // The maker's mark at the bottom of the panel, and the headphone socket on the right.
        let mark = NSMutableAttributedString(string: "digi ", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1), .obliqueness: 0.18])
        mark.append(NSAttributedString(string: "002", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .heavy), .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1), .obliqueness: 0.18]))
        mark.draw(at: NSPoint(x: 210, y: panelBottom - 14))
        NSColor(calibratedWhite: 0.5, alpha: 1).setStroke()
        let jack = NSBezierPath(ovalIn: NSRect(x: 516, y: 64, width: 12, height: 12))
        jack.lineWidth = 2
        jack.stroke()
        NSColor(calibratedWhite: 0.05, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 519, y: 67, width: 6, height: 6)).fill()

        let labelFont = NSFont.systemFont(ofSize: 6.5, weight: .medium)
        let mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        let stripX0: CGFloat = 64, stripW: CGFloat = 42

        // Top band: mic gain knobs on the left, monitor knobs on the right (not controlled).
        for i in 0..<4 { knob(at: NSPoint(x: 80 + CGFloat(i) * 26, y: 18), radius: 7) }
        knob(at: NSPoint(x: 476, y: 18), radius: 8)
        knob(at: NSPoint(x: 514, y: 18), radius: 8)
        // Sample rate LEDs between displays 10 and the right edge.
        for i in 0..<4 { led(at: NSPoint(x: 498 + CGFloat(i) * 11, y: 44), on: false, colour: .green, radius: 2) }

        for channel in 0..<8 {
            let x = stripX0 + CGFloat(channel) * stripW
            drawDisplay(displays[channel], inverse: inverse[channel], in: NSRect(x: x + 3, y: 34, width: 36, height: 18), font: mono)
            drawRing(rings[channel], centre: NSPoint(x: x + 21, y: 90))
            // Record Ready LED, then SEL, SOLO, MUTE.
            led(at: NSPoint(x: x + 6, y: 113), on: leds[.recordReady(channel)] ?? false, colour: .red, radius: 2)
            let green = leds[.select(channel)] ?? false, red = leds[.selectRed(channel)] ?? false
            button("SEL", in: NSRect(x: x + 6, y: 118, width: 30, height: 12), font: labelFont,
                   led: green || red, colour: green && red ? .orange : red ? .red : .green)
            button("SOLO", in: NSRect(x: x + 6, y: 134, width: 30, height: 12), font: labelFont,
                   led: leds[.solo(channel)] ?? false, colour: .yellow)
            button("MUTE", in: NSRect(x: x + 6, y: 150, width: 30, height: 12), font: labelFont,
                   led: leds[.mute(channel)] ?? false, colour: .orange)
            let slot = NSRect(x: x + 19, y: 170, width: 4, height: 128)
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            slot.fill()
            let capY = slot.maxY - 6 - CGFloat(faders[channel]) / 1023 * (slot.height - 12)
            NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 13, y: capY - 5, width: 16, height: 10), xRadius: 2, yRadius: 2).fill()
            NSColor(calibratedWhite: 0.6, alpha: 1).setFill()
            NSRect(x: x + 13, y: capY - 0.5, width: 16, height: 1).fill()
        }

        // Left column: encoder assignment, channel view A–E, modifiers.
        let leftNames = ["Pan", "Send", "Insert", "A", "B", "C", "D", "E"]
        for (i, name) in leftNames.enumerated() {
            namedButton(name, label: name, in: NSRect(x: 14, y: 114 + CGFloat(i) * 15, width: 44, height: 12), font: labelFont)
        }
        for (i, name) in ["Shift", "Option", "Control", "Command"].enumerated() {
            namedButton(name, label: ["Shift", "Opt", "Ctl", "Cmd"][i], in: NSRect(x: 14, y: 242 + CGFloat(i) * 15, width: 44, height: 12), font: labelFont)
        }

        // Displays 9 and 10 sit right of the strips, above the right-hand block.
        drawDisplay(displays[8], inverse: inverse[8], in: NSRect(x: 408, y: 34, width: 36, height: 18), font: mono)
        drawDisplay(displays[9], inverse: inverse[9], in: NSRect(x: 450, y: 34, width: 36, height: 18), font: mono)

        // Right-hand block: six columns of small buttons.
        let rx: CGFloat = 405, bw: CGFloat = 25, bh: CGFloat = 11, gap: CGFloat = 2
        func cell(_ col: Int, _ row: Int) -> NSRect {
            NSRect(x: rx + CGFloat(col) * (bw + gap), y: 70 + CGFloat(row) * (bh + 4), width: bw, height: bh)
        }
        let rows: [[(String, String)]] = [
            [("EQ", "EQ"), ("Dynamics", "Dyn"), ("Insert (console view)", "Ins"), ("Pan/Send", "P/S"), ("Master Bypass", "MBy")],
            [("Page Left", "◀Pg"), ("Page Right", "Pg▶"), ("Esc", "Esc"), ("Display", "Disp"), ("Enter", "Entr")],
            [("Undo", "Undo"), ("Meter", "Mtr"), ("Rec (meter)", "Rec"), ("Flip", "Flip"), ("Master Faders", "MFd")],
            [("Bank", "Bank"), ("Nudge", "Nudg"), ("Zoom", "Zoom")],
            [("F1", "F1"), ("F2", "F2"), ("F3", "F3"), ("F4", "F4"), ("F5", "F5")],
        ]
        face = NSColor(calibratedRed: 0.40, green: 0.41, blue: 0.45, alpha: 1)
        for (r, row) in rows.enumerated() {
            for (c, (name, label)) in row.enumerated() { namedButton(name, label: label, in: cell(c, r), font: labelFont) }
        }
        face = Self.buttonFace
        // The round arrow pad, with the window buttons beside it.
        let pad = NSPoint(x: 448, y: 198)
        Self.buttonFace.setFill()
        NSBezierPath(ovalIn: NSRect(x: pad.x - 26, y: pad.y - 26, width: 52, height: 52)).fill()
        Self.panel.setFill()
        NSBezierPath(ovalIn: NSRect(x: pad.x - 8, y: pad.y - 8, width: 16, height: 16)).fill()
        let arrowFont = NSFont.systemFont(ofSize: 8, weight: .bold)
        for (label, dx, dy) in [("▲", 0.0, -18.0), ("▼", 0.0, 12.0), ("◀", -19.0, -3.0), ("▶", 13.0, -3.0)] as [(String, Double, Double)] {
            NSString(string: label).draw(at: NSPoint(x: pad.x + CGFloat(dx) - 3, y: pad.y + CGFloat(dy) - 3),
                                         withAttributes: [.font: arrowFont, .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1)])
        }
        for (i, (name, label)) in [("Mix", "Mix"), ("Edit", "Edit"), ("Plug-in", "Plug")].enumerated() {
            namedButton(name, label: label, in: NSRect(x: 486, y: 176 + CGFloat(i) * 15, width: 44, height: 12), font: labelFont)
        }
        // Transport along the bottom.
        let top = [("Loop Play", "Loop"), ("Loop Rec", "LRec"), ("Quick Punch", "QPch"), ("RTZ", "RTZ")]
        for (i, (name, label)) in top.enumerated() {
            namedButton(name, label: label, in: NSRect(x: rx + CGFloat(i) * 33, y: 262, width: 31, height: 12), font: labelFont)
        }
        let transport = [("Rewind", "◀◀", Self.buttonFace), ("Fast Forward", "▶▶", Self.buttonFace), ("Stop", "■", Self.buttonFace),
                         ("Play", "▶", NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.30, alpha: 1)),
                         ("Record", "●", NSColor(calibratedRed: 0.65, green: 0.20, blue: 0.20, alpha: 1))]
        for (i, (_, label, face)) in transport.enumerated() {
            let rect = NSRect(x: rx + CGFloat(i) * 26.5, y: 282, width: 25, height: 24)
            face.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            NSString(string: label).draw(in: NSRect(x: rect.minX, y: rect.minY + 6, width: rect.width, height: 14),
                                         withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold),
                                                          .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1), .paragraphStyle: style])
        }
    }

    private func knob(at centre: NSPoint, radius: CGFloat) {
        NSColor(calibratedWhite: 0.35, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)).fill()
        NSColor(calibratedWhite: 0.8, alpha: 1).setFill()
        NSRect(x: centre.x - 0.5, y: centre.y - radius + 1, width: 1, height: radius * 0.6).fill()
    }

    private func led(at centre: NSPoint, on: Bool, colour: NSColor, radius: CGFloat) {
        if on {
            colour.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: centre.x - radius * 2, y: centre.y - radius * 2, width: radius * 4, height: radius * 4)).fill()
        }
        (on ? colour : Self.ledOff).setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    /// A button with an LED in its top-left corner when `led` is given.
    /// Buttons on the dark upper area are lighter than those on the silver panel.
    private var face = DeskView.buttonFace

    private func button(_ label: String, in rect: NSRect, font: NSFont, led: Bool?, colour: NSColor) {
        face.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        // The LED sits in the top-left corner, as on the desk, and the label is centred.
        if let led { self.led(at: NSPoint(x: rect.minX + 3, y: rect.minY + 3), on: led, colour: colour, radius: 1.5) }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let inset: CGFloat = led == nil ? 0 : 3
        NSString(string: label).draw(in: NSRect(x: rect.minX + inset, y: rect.minY + 1.5, width: rect.width - inset, height: rect.height),
                                     withAttributes: [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1), .paragraphStyle: style])
    }

    /// A button looked up by its desk name; it gets an LED if the real one has one.
    private func namedButton(_ name: String, label: String, in rect: NSRect, font: NSFont) {
        guard let b = Button.named(name) else { return }
        let hasLED = Button.ledButtons.contains(b)
        button(label, in: rect, font: font, led: hasLED ? (leds[b] ?? false) : nil, colour: .green)
    }

    private func drawRing(_ ring: Ring, centre: NSPoint) {
        let radius: CGFloat = 13
        for led in 1...14 {
            // LEDs 1 to 14 sweep from 7 o'clock round the top to 5 o'clock.
            let angle = (210.0 - Double(led - 1) * (240.0 / 13.0)) * .pi / 180
            let point = NSPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y - radius * CGFloat(sin(angle)))
            self.led(at: point, on: ring.leds & (1 << (led - 1)) != 0, colour: Self.amber, radius: 1.6)
        }
        let last: NSColor = ring.lastGreen && ring.lastRed ? .orange : ring.lastRed ? .red : .green
        self.led(at: NSPoint(x: centre.x, y: centre.y + radius + 4), on: ring.lastGreen || ring.lastRed, colour: last, radius: 1.6)
        knob(at: centre, radius: 7)
    }

    // MARK: Photo overlay

    /// The photo scaled to fit, with the live state drawn at the layout's positions.
    private func drawOverlay(_ image: NSImage, _ layout: DeskLayout) {
        let size = image.size
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let drawn = NSRect(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2,
                           width: size.width * scale, height: size.height * scale)
        NSGraphicsContext.current?.cgContext.saveGState()
        // The view is flipped; draw the image upright inside it.
        image.draw(in: drawn, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.current?.cgContext.restoreGState()
        func px(_ fx: Double) -> CGFloat { drawn.minX + CGFloat(fx) * drawn.width }
        func py(_ fy: Double) -> CGFloat { drawn.minY + CGFloat(fy) * drawn.height }
        func pw(_ fw: Double) -> CGFloat { CGFloat(fw) * drawn.width }
        func ph(_ fh: Double) -> CGFloat { CGFloat(fh) * drawn.height }

        let s = layout.strips
        let fontSize = max(7, ph(s.displayH) * 0.6)
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        for channel in 0..<min(8, s.x.count) {
            let x = s.x[channel]
            drawDisplay(displays[channel], inverse: inverse[channel],
                        in: NSRect(x: px(x), y: py(s.displayY), width: pw(s.displayW), height: ph(s.displayH)), font: mono)
            drawRingGlow(rings[channel], centre: NSPoint(x: px(x + s.ringX), y: py(s.ringY)), radius: pw(s.ringR))
            let green = leds[.select(channel)] ?? false, red = leds[.selectRed(channel)] ?? false
            let ledR = pw(s.ledR)
            if green || red { glow(at: NSPoint(x: px(x + s.ledX), y: py(s.selY)), radius: ledR, colour: green && red ? .orange : red ? .red : .green) }
            if leds[.solo(channel)] ?? false { glow(at: NSPoint(x: px(x + s.ledX), y: py(s.soloY)), radius: ledR, colour: .yellow) }
            if leds[.mute(channel)] ?? false { glow(at: NSPoint(x: px(x + s.ledX), y: py(s.muteY)), radius: ledR, colour: .orange) }
            if leds[.recordReady(channel)] ?? false { glow(at: NSPoint(x: px(x + s.ledX), y: py(s.recY)), radius: ledR, colour: .red) }
            let capY = py(s.faderBottom) - CGFloat(faders[channel]) / 1023 * (py(s.faderBottom) - py(s.faderTop))
            NSColor(calibratedWhite: 0.9, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: NSRect(x: px(x + s.faderX) - pw(s.capW) / 2, y: capY - ph(s.capH) / 2,
                                             width: pw(s.capW), height: ph(s.capH)), xRadius: 2, yRadius: 2).fill()
        }
        if layout.display9.count == 2 {
            drawDisplay(displays[8], inverse: inverse[8], in: NSRect(x: px(layout.display9[0]), y: py(layout.display9[1]),
                                                                     width: pw(s.displayW), height: ph(s.displayH)), font: mono)
        }
        if layout.display10.count == 2 {
            drawDisplay(displays[9], inverse: inverse[9], in: NSRect(x: px(layout.display10[0]), y: py(layout.display10[1]),
                                                                      width: pw(s.displayW), height: ph(s.displayH)), font: mono)
        }
        for (name, point) in layout.leds where point.count == 2 {
            guard let button = Button.named(name), leds[button] ?? false else { continue }
            glow(at: NSPoint(x: px(point[0]), y: py(point[1])), radius: pw(layout.ledR), colour: .green)
        }
    }

    private func glow(at centre: NSPoint, radius: CGFloat, colour: NSColor) {
        colour.withAlphaComponent(0.35).setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - radius * 2, y: centre.y - radius * 2, width: radius * 4, height: radius * 4)).fill()
        colour.setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    private func drawRingGlow(_ ring: Ring, centre: NSPoint, radius: CGFloat) {
        for led in 1...14 where ring.leds & (1 << (led - 1)) != 0 {
            let angle = (210.0 - Double(led - 1) * (240.0 / 13.0)) * .pi / 180
            let point = NSPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y - radius * CGFloat(sin(angle)))
            glow(at: point, radius: max(1.5, radius * 0.12), colour: .orange)
        }
        if ring.lastGreen || ring.lastRed {
            glow(at: NSPoint(x: centre.x, y: centre.y - radius * 1.25), radius: max(1.5, radius * 0.12),
                 colour: ring.lastGreen && ring.lastRed ? .orange : ring.lastRed ? .red : .green)
        }
    }

    private func drawDisplay(_ text: String, inverse: Bool, in rect: NSRect, font: NSFont) {
        (inverse ? Self.amber : NSColor(calibratedWhite: 0.05, alpha: 1)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        let colour: NSColor = inverse ? .black : Self.amber
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour, .paragraphStyle: style]
        let textHeight = font.ascender - font.descender
        NSString(string: text).draw(in: NSRect(x: rect.minX, y: rect.midY - textHeight / 2, width: rect.width, height: textHeight),
                                    withAttributes: attributes)
    }



}
