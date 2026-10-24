/// The subset of the Mackie Control (MCU) protocol the bridge speaks to Logic.
/// Channels are 0-based (0 = strip 1). Fader values are MCU's 14-bit range, 0 to 16383.

public enum MCUMessage: Equatable {
    case fader(channel: Int, value: Int)
    case faderTouch(channel: Int, touched: Bool)
    /// A button press/release from the surface, or an LED state from the host.
    case note(MCUNote, on: Bool)
    /// Positive steps are clockwise.
    case vpot(channel: Int, steps: Int)
    /// V-Pot ring state from the host: `B0 3n vv`. Position 0 is off, 1–11 is the LED,
    /// 6 being the centre.
    case vpotRing(channel: Int, centre: Bool, mode: VPotMode, position: Int)
    /// LCD text from the host, written from `offset` into two lines of 56 characters.
    case lcd(offset: Int, text: [UInt8])
    /// The host asks for an LED to flash (note velocity 1).
    case ledFlash(MCUNote)
    /// Channel meter from the host: `D0 (channel << 4 | level)`. Levels 0–12 are signal,
    /// 14 sets the clip indicator and 15 clears it.
    case meter(channel: Int, level: Int)
    /// One character of the host's seven-segment displays: positions 0–9 are the timecode,
    /// right to left, and 10–11 the two assignment characters.
    case sevenSegment(position: Int, character: Character, dot: Bool)
}

/// How the host wants a V-Pot ring drawn (bits 4–5 of the ring byte).
public enum VPotMode: Int, Equatable {
    case dot = 0        // one LED
    case boostCut = 1   // from the centre out to the position
    case wrap = 2       // from the left end up to the position
    case spread = 3     // from the centre out both ways
}

/// MCU note numbers for the buttons the bridge maps.
public struct MCUNote: Hashable {
    public let number: UInt8

    public init(_ number: UInt8) { self.number = number }

    public static func recArm(_ channel: Int) -> MCUNote { MCUNote(0x00 + UInt8(channel)) }
    public static func solo(_ channel: Int) -> MCUNote { MCUNote(0x08 + UInt8(channel)) }
    public static func mute(_ channel: Int) -> MCUNote { MCUNote(0x10 + UInt8(channel)) }
    public static func select(_ channel: Int) -> MCUNote { MCUNote(0x18 + UInt8(channel)) }
    public static func faderTouch(_ channel: Int) -> MCUNote { MCUNote(0x68 + UInt8(channel)) }
    /// F1 to F8.
    public static func function(_ number: Int) -> MCUNote { MCUNote(0x36 + UInt8(number - 1)) }

    // Assignment
    public static let assignTrack = MCUNote(0x28)
    public static let assignSend = MCUNote(0x29)
    public static let assignPan = MCUNote(0x2A)
    public static let assignPlugin = MCUNote(0x2B)
    public static let assignEQ = MCUNote(0x2C)
    public static let assignInstrument = MCUNote(0x2D)
    // Fader banks
    public static let bankLeft = MCUNote(0x2E)
    public static let bankRight = MCUNote(0x2F)
    public static let channelLeft = MCUNote(0x30)
    public static let channelRight = MCUNote(0x31)
    public static let flip = MCUNote(0x32)
    public static let globalView = MCUNote(0x33)
    // Display
    public static let nameValue = MCUNote(0x34)
    public static let smpteBeats = MCUNote(0x35)
    // Modifiers
    public static let shift = MCUNote(0x46)
    public static let option = MCUNote(0x47)
    public static let control = MCUNote(0x48)
    public static let command = MCUNote(0x49)
    // Utilities
    public static let save = MCUNote(0x50)
    public static let undo = MCUNote(0x51)
    public static let cancel = MCUNote(0x52)
    public static let enter = MCUNote(0x53)
    // Transport area
    public static let marker = MCUNote(0x54)
    public static let nudge = MCUNote(0x55)
    public static let cycle = MCUNote(0x56)
    public static let drop = MCUNote(0x57)
    public static let replace = MCUNote(0x58)
    public static let click = MCUNote(0x59)
    public static let rewind = MCUNote(0x5B)
    public static let fastForward = MCUNote(0x5C)
    public static let stop = MCUNote(0x5D)
    public static let play = MCUNote(0x5E)
    public static let record = MCUNote(0x5F)
    // Cursor
    public static let up = MCUNote(0x60)
    public static let down = MCUNote(0x61)
    public static let left = MCUNote(0x62)
    public static let right = MCUNote(0x63)
    public static let zoom = MCUNote(0x64)
    public static let scrub = MCUNote(0x65)
}

public enum MCUEncoder {
    public static func encode(_ message: MCUMessage) -> [UInt8] {
        switch message {
        case let .fader(channel, value):
            let v = min(max(value, 0), 0x3FFF)
            return [0xE0 | UInt8(channel), UInt8(v & 0x7F), UInt8(v >> 7)]
        case let .faderTouch(channel, touched):
            return [0x90, MCUNote.faderTouch(channel).number, touched ? 0x7F : 0x00]
        case let .note(note, on):
            return [0x90, note.number, on ? 0x7F : 0x00]
        case let .vpot(channel, steps):
            // Sign and magnitude: bit 6 set means anticlockwise.
            let magnitude = UInt8(min(abs(steps), 0x3F))
            return [0xB0, 0x10 + UInt8(channel), steps < 0 ? 0x40 | magnitude : magnitude]
        case let .vpotRing(channel, centre, mode, position):
            return [0xB0, 0x30 + UInt8(channel),
                    (centre ? 0x40 : 0) | UInt8(mode.rawValue) << 4 | UInt8(min(max(position, 0), 11))]
        case let .lcd(offset, text):
            return MCUDecoder.lcdHeader + [UInt8(offset)] + text + [0xF7]
        case let .ledFlash(note):
            return [0x90, note.number, 0x01]
        case let .meter(channel, level):
            return [0xD0, UInt8(channel) << 4 | UInt8(level & 0x0F)]
        case let .sevenSegment(position, character, dot):
            // The display takes ASCII 0x20–0x5F in six bits: 0x40–0x5F are sent as 0x00–0x1F.
            let ascii = UInt8(character.asciiValue ?? 0x20)
            let code = ascii >= 0x40 ? ascii - 0x40 : ascii
            return [0xB0, 0x40 + UInt8(position), code & 0x3F | (dot ? 0x40 : 0)]
        }
    }
}

/// Decodes what Logic sends to an MCU: fader positions, LED states, V-Pot rings and LCD
/// text. Everything else (meters, timecode) is passed back as unhandled for now.
public struct MCUDecoder {
    /// Logic writes the LCD with `F0 00 00 66 14 12 offset text F7`; 14 is the MCU device id.
    static let lcdHeader: [UInt8] = [0xF0, 0x00, 0x00, 0x66, 0x14, 0x12]

    private var runningStatus: UInt8 = 0
    private var pending: [UInt8] = []
    /// A SysEx message being collected, which may span packets.
    private var sysex: [UInt8]?

    public init() {}

    public mutating func decode(_ bytes: [UInt8]) -> [MCUMessage] {
        var messages: [MCUMessage] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte == 0xF0 {
                sysex = [byte]
                runningStatus = 0
                pending.removeAll()
                continue
            }
            if sysex != nil {
                if byte == 0xF7 {
                    sysex!.append(byte)
                    if let message = sysexMessage(sysex!) { messages.append(message) }
                    sysex = nil
                } else if byte >= 0x80 {
                    sysex = nil          // another status byte: the SysEx was cut short
                } else {
                    sysex!.append(byte)
                }
                if byte < 0x80 || byte == 0xF7 { continue }
            }
            if byte >= 0x80 {
                runningStatus = byte >= 0xF0 ? 0 : byte
                pending.removeAll()
                continue
            }
            guard runningStatus != 0 else { continue }
            pending.append(byte)
            let needed = (runningStatus & 0xF0 == 0xC0 || runningStatus & 0xF0 == 0xD0) ? 1 : 2
            guard pending.count == needed else { continue }
            if needed == 2, let message = message(runningStatus, pending[0], pending[1]) {
                messages.append(message)
            } else if needed == 1, runningStatus & 0xF0 == 0xD0 {
                messages.append(.meter(channel: Int(pending[0] >> 4), level: Int(pending[0] & 0x0F)))
            }
            pending.removeAll()
        }
        return messages
    }

    private func message(_ status: UInt8, _ data1: UInt8, _ data2: UInt8) -> MCUMessage? {
        switch status & 0xF0 {
        case 0xE0:
            let channel = Int(status & 0x0F)
            guard channel < 8 else { return nil }      // channel 9 is the master fader
            return .fader(channel: channel, value: Int(data1) | Int(data2) << 7)
        case 0x90 where data2 == 0x01:
            return .ledFlash(MCUNote(data1))
        case 0x90:
            return .note(MCUNote(data1), on: data2 != 0)
        case 0x80:
            return .note(MCUNote(data1), on: false)
        case 0xB0 where (0x40...0x4B).contains(data1):
            let code = data2 & 0x3F
            let ascii = code < 0x20 ? code + 0x40 : code
            return .sevenSegment(position: Int(data1 - 0x40), character: Character(UnicodeScalar(ascii)), dot: data2 & 0x40 != 0)
        case 0xB0 where data1 & 0xF8 == 0x30:
            return .vpotRing(channel: Int(data1 & 0x07), centre: data2 & 0x40 != 0,
                             mode: VPotMode(rawValue: Int(data2 >> 4 & 0x03))!, position: Int(data2 & 0x0F))
        default:
            return nil
        }
    }

    private func sysexMessage(_ bytes: [UInt8]) -> MCUMessage? {
        guard bytes.count >= Self.lcdHeader.count + 2, bytes.starts(with: Self.lcdHeader) else { return nil }
        let offset = Int(bytes[Self.lcdHeader.count])
        return .lcd(offset: offset, text: Array(bytes[(Self.lcdHeader.count + 1)..<(bytes.count - 1)]))
    }
}
