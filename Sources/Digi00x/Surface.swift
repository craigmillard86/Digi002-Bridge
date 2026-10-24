/// The Digi 002 control surface protocol on the "Port 3 (Control)" MIDI port.
/// See docs/protocol.md for where each format comes from.
///
/// Channels are 0-based here (0 = channel strip 1). Fader positions are the desk's
/// native 10-bit range, 0 (bottom) to 1023 (top).

/// A button, addressed by its place in the desk's button grid: the note number is the
/// row and the low six bits of the velocity are the column. The same address lights its LED.
public struct Button: Hashable, CustomStringConvertible {
    public let row: UInt8
    public let column: UInt8

    public init(row: UInt8, column: UInt8) {
        self.row = row
        self.column = column
    }

    public static func select(_ channel: Int) -> Button { Button(row: 0x00, column: UInt8(channel)) }
    public static func solo(_ channel: Int) -> Button { Button(row: 0x02, column: UInt8(channel)) }
    public static func mute(_ channel: Int) -> Button { Button(row: 0x03, column: UInt8(channel)) }
    /// Not a button: the red element of the two-colour SEL LED (row 00 is the green one,
    /// both together show orange). No switch reports on this row.
    public static func selectRed(_ channel: Int) -> Button { Button(row: 0x01, column: UInt8(channel)) }
    /// Not a button: the small red Record Ready LED above each SEL switch.
    public static func recordReady(_ channel: Int) -> Button { Button(row: 0x04, column: UInt8(channel)) }

    /// The channel strip this button belongs to, or nil for buttons outside the strips.
    public var channel: Int? { column < 8 ? Int(column) : nil }

    public var description: String { Button.names[self] ?? "row \(row) col \(column)" }

    /// Names as printed on the desk, for logs and config files.
    public static let names: [Button: String] = {
        var names: [Button: String] = [:]
        for channel in 0..<8 {
            names[.select(channel)] = "SEL \(channel + 1)"
            names[.solo(channel)] = "SOLO \(channel + 1)"
            names[.mute(channel)] = "MUTE \(channel + 1)"
        }
        let columns: [UInt8: [String?]] = [
            0x0A: ["Pan", "Send", "Insert", "A", "B", "C", "D", "E",
                   "Shift", "Option", "Control", "Command"],
            0x0B: ["EQ", "Dynamics", "Insert (console view)", "Pan/Send", "Page Left",
                   "Page Right", "Master Bypass", "Esc", "Display"],
            0x0C: ["Enter", "Undo", nil, "Rec (meter)", "Meter"],
            0x0D: ["Flip", "Master Faders", "Bank", "Nudge", "Zoom", "Left", "Right", "Up", "Down",
                   "F1", "F2", "F3", "F4", "F5"],
            0x0E: ["Plug-in", "Mix", "Edit", "Loop Play", "Loop Rec", "Quick Punch",
                   "RTZ", "Rewind", "Fast Forward", "Stop", "Play", "Record"],
        ]
        for (column, rows) in columns {
            for (row, name) in rows.enumerated() {
                if let name { names[Button(row: UInt8(row), column: column)] = name }
            }
        }
        return names
    }()

    public static func named(_ name: String) -> Button? {
        names.first { $0.value == name }?.key
    }
}

/// Something the desk reports.
public enum SurfaceEvent: Equatable {
    case fader(channel: Int, position: Int)
    case faderTouch(channel: Int, touched: Bool)
    case button(Button, pressed: Bool)
    /// Positive steps are clockwise. Faster turns give larger steps.
    case encoder(channel: Int, steps: Int)
}

/// One encoder ring: LEDs 1 to 14 in the arc, plus a two-colour 15th LED
/// (docs/protocol.md, Encoder rings).
public struct Ring: Hashable {
    /// Bit n−1 lights LED n.
    public var leds: UInt16
    public var lastGreen: Bool
    public var lastRed: Bool

    public init(leds: UInt16 = 0, lastGreen: Bool = false, lastRed: Bool = false) {
        self.leds = leds
        self.lastGreen = lastGreen
        self.lastRed = lastRed
    }

    public static let off = Ring()

    public mutating func light(_ led: Int) {
        guard (1...14).contains(led) else { return }
        leds |= 1 << (led - 1)
    }

    public mutating func light(_ range: ClosedRange<Int>) {
        for led in range { light(led) }
    }
}

/// Something to tell the desk.
public enum SurfaceCommand: Hashable {
    case fader(channel: Int, position: Int)
    case led(Button, on: Bool)
    case ring(channel: Int, Ring)
    /// Four characters on one display. Strips 0–7 sit above the channels; 8 and 9 also
    /// exist. Inverse shows light text on a dark background.
    case display(strip: Int, text: String, inverse: Bool)
}

/// Turns the desk's MIDI bytes into events. Keeps state between packets, because a
/// fader's coarse and fine values arrive as separate messages.
public struct SurfaceDecoder {
    /// Row 05 columns 0-7 are fader touch rather than buttons.
    static let touchRow: UInt8 = 0x05

    private var runningStatus: UInt8 = 0
    private var pending: [UInt8] = []
    private var coarse = [UInt8](repeating: 0, count: 8)

    public init() {}

    public mutating func decode(_ bytes: [UInt8]) -> [SurfaceEvent] {
        var events: [SurfaceEvent] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }             // real-time bytes can appear anywhere
            if byte >= 0x80 {
                runningStatus = byte >= 0xF0 ? 0 : byte
                pending.removeAll()
                continue
            }
            guard runningStatus != 0 else { continue }   // data with no status, or inside SysEx
            pending.append(byte)
            if pending.count == 2 {
                if let event = message(runningStatus, pending[0], pending[1]) { events.append(event) }
                pending.removeAll()
            }
        }
        return events
    }

    private mutating func message(_ status: UInt8, _ data1: UInt8, _ data2: UInt8) -> SurfaceEvent? {
        switch (status, data1) {
        case (0xB0, 0x00...0x07):
            coarse[Int(data1)] = data2
            return nil
        case (0xB0, 0x20...0x27):
            let channel = Int(data1 - 0x20)
            return .fader(channel: channel, position: Int(coarse[channel]) << 3 | Int(data2) >> 4)
        case (0xB0, 0x40...0x47):
            return .encoder(channel: Int(data1 - 0x40), steps: Int(data2) - 0x40)
        case (0x90, _):
            let pressed = data2 & 0x40 != 0
            let column = data2 & 0x3F
            if data1 == Self.touchRow && column < 8 {
                return .faderTouch(channel: Int(column), touched: pressed)
            }
            return .button(Button(row: data1, column: column), pressed: pressed)
        default:
            return nil
        }
    }
}

public enum SurfaceEncoder {
    public static func encode(_ command: SurfaceCommand) -> [UInt8] {
        switch command {
        case let .fader(channel, position):
            let value = min(max(position, 0), 1023)
            let cc = UInt8(channel)
            // The desk only accepts fader moves written with running status.
            return [0xB0, cc, UInt8(value >> 3), cc + 0x20, UInt8(value & 0x07) << 4]
        case let .led(button, on):
            return [0x90, button.row, button.column | (on ? 0x40 : 0)]
        case let .ring(channel, ring):
            let strip = UInt8(channel) | (ring.lastGreen ? 0x20 : 0) | (ring.lastRed ? 0x40 : 0)
            return [0xF0, 0x13, 0x00, 0x00, strip, UInt8(ring.leds >> 7 & 0x7F), UInt8(ring.leds & 0x7F), 0xF7]
        case let .display(strip, text, inverse):
            // Characters are 8-bit; the top bit of each travels in the mode and high-bits bytes.
            var chars = text.unicodeScalars.prefix(4).map { $0.value < 0x100 ? UInt8($0.value) : 0x3F }
            while chars.count < 4 { chars.append(0x20) }
            let mode: UInt8 = (inverse ? 0x7C : 0x78) | chars[0] >> 7
            let high: UInt8 = (chars[1] >> 7) << 4 | (chars[2] >> 7) << 2 | chars[3] >> 7
            return [0xF0, 0x13, 0x00, 0x40, UInt8(strip), mode, high] + chars.map { $0 & 0x7F } + [0xF7]
        }
    }
}
