import Foundation
import Digi00x
import MCU

/// Translates between the Digi 002 surface and Mackie Control. Holds no I/O; the caller
/// feeds it decoded messages and sends whatever it returns. docs/mapping.md describes
/// what each button does.
public struct Bridge {
    public let config: BridgeConfig

    /// Desk buttons with a fixed one-to-one MCU meaning, both for presses and for LEDs.
    /// The configurable ones (A–E, Master Bypass, Master Faders) are added per instance
    /// from the config; see `buttonMap`.
    public static let fixedButtonMap: [Button: MCUNote] = {
        var map: [Button: MCUNote] = [:]
        for channel in 0..<8 {
            map[.select(channel)] = .select(channel)
            map[.solo(channel)] = .solo(channel)
            map[.mute(channel)] = .mute(channel)
        }
        let named: [(String, MCUNote)] = [
            ("Shift", .shift), ("Option", .option), ("Control", .control), ("Command", .command),
            ("Up", .up), ("Down", .down), ("Zoom", .zoom), ("Flip", .flip),
            ("Enter", .enter), ("Undo", .undo), ("Esc", .cancel), ("Display", .nameValue),
            ("Pan", .assignPan), ("Send", .assignSend), ("Insert", .assignPlugin),
            ("EQ", .assignEQ), ("Dynamics", .assignInstrument),
            ("Insert (console view)", .assignPlugin), ("Pan/Send", .assignPan),
            ("Page Left", .bankLeft), ("Page Right", .bankRight),
            ("F1", .function(1)), ("F2", .function(2)), ("F3", .function(3)),
            ("F4", .function(4)), ("F5", .function(5)),
            ("Mix", .function(6)), ("Edit", .function(7)), ("Plug-in", .function(8)),
            ("Loop Play", .cycle), ("Quick Punch", .drop), ("Loop Rec", .replace),
            ("Rewind", .rewind), ("Fast Forward", .fastForward),
            ("Stop", .stop), ("Play", .play), ("Record", .record),
        ]
        for (name, note) in named {
            guard let button = Button.named(name) else { preconditionFailure("no button named \(name)") }
            map[button] = note
        }
        return map
    }()

    /// The fixed map plus the configured buttons.
    public let buttonMap: [Button: MCUNote]
    /// What the configured buttons send instead while the desk's Shift is held.
    public let shiftButtonMap: [Button: MCUNote]

    /// Several desk buttons can share one MCU note (e.g. both Insert buttons); every one
    /// of them shows that note's LED.
    private let buttonsForNote: [MCUNote: [Button]]

    static func makeButtonMap(_ config: BridgeConfig) -> [Button: MCUNote] {
        var map = fixedButtonMap
        for name in BridgeConfig.configurableButtons {
            guard let button = Button.named(name) else { preconditionFailure("no button named \(name)") }
            if let note = config.action(for: name).note { map[button] = note }
        }
        return map
    }

    static func makeShiftButtonMap(_ config: BridgeConfig) -> [Button: MCUNote] {
        var map: [Button: MCUNote] = [:]
        for name in BridgeConfig.configurableButtons {
            guard let button = Button.named(name) else { preconditionFailure("no button named \(name)") }
            if let note = config.shiftAction(for: name).note { map[button] = note }
        }
        return map
    }

    static func makeButtonsForNote(_ map: [Button: MCUNote], _ shiftMap: [Button: MCUNote],
                                   _ config: BridgeConfig) -> [MCUNote: [Button]] {
        var lookup = Dictionary(grouping: map.keys, by: { map[$0]! })
        // A button that only does something with Shift shows that function's LED.
        for (button, note) in shiftMap where map[button] == nil {
            lookup[note, default: []].append(button)
        }
        // Record arm has no button of its own; it lights the Record Ready LED above SEL,
        // and the red half of the SEL LED too if asked.
        for channel in 0..<8 {
            lookup[.recArm(channel), default: []].append(.recordReady(channel))
            if config.armedSelectRed { lookup[.recArm(channel), default: []].append(.selectRed(channel)) }
        }
        return lookup
    }

    static let bankButton = Button.named("Bank")!
    static let nudgeButton = Button.named("Nudge")!
    static let leftButton = Button.named("Left")!
    static let rightButton = Button.named("Right")!
    static let recButton = Button.named("Rec (meter)")!
    static let shiftButton = Button.named("Shift")!
    static let meterButton = Button.named("Meter")!
    static let rtzButton = Button.named("RTZ")!

    /// What the right-hand display shows for each V-Pot assignment Logic lights.
    static let assignmentNames: [MCUNote: String] = [
        .assignTrack: "Trk", .assignSend: "Send", .assignPan: "Pan",
        .assignPlugin: "Plug", .assignEQ: "EQ", .assignInstrument: "Inst",
    ]
    /// Display 9 (strip 8) shows the assignment, display 10 (strip 9) the position.
    static let assignmentStrip = 8
    static let positionStrip = 9

    /// How often the caller must call `tick()`.
    public static let tickSeconds = 0.1
    static let peakHoldTicks = 10     // 1 s before a meter's peak dot starts to fall
    static let clipHoldTicks = 20     // 2 s of red after a clip, unless Logic clears it first
    static let flashHalfPeriodTicks = 5   // flashing LEDs change state every 0.5 s
    static let scrollHoldTicks = 10       // a scrolling name rests 1 s at each end
    static let scrollStepTicks = 3        // and moves one character every 0.3 s

    /// What the nav pad's left and right arrows do.
    public enum NavMode: Equatable {
        case bank      // move the fader bank by 8 tracks
        case channel   // move it by 1 track
    }

    public private(set) var navMode: NavMode
    private var logicZoomOn = false
    private var recHeld = false
    /// The desk's Shift is held (or any button configured as Shift).
    private var shiftHeld = false
    /// The MCU note sent for each held desk button, so the release goes to the same
    /// note even if a mode changed in between.
    private var heldNotes: [Button: MCUNote] = [:]
    private var touched = Set<Int>()
    /// Last position the desk reported for each fader, sent back on release so the motor
    /// holds it even if Logic does not echo the value.
    private var deskPosition = [Int](repeating: 0, count: 8)
    /// Last LED state Logic asked for, so it can be replayed when the desk wakes up.
    private var ledState: [Button: Bool] = [:]
    private var logicFaderSeen = Set<Int>()
    /// Logic's V-Pot ring for each channel.
    private var ringState: [Int: Ring] = [:]
    /// What each desk ring currently shows (V-Pot or meter), so unchanged rings are not resent.
    private var ringShown: [Int: Ring] = [:]
    /// Rings show Logic's meters instead of the V-Pots, as Pro Tools did; the Meter button toggles it.
    public private(set) var meterMode: Bool
    private var meterLevel = [Int](repeating: 0, count: 8)
    private var meterPeak = [Int](repeating: 0, count: 8)
    private var meterPeakAge = [Int](repeating: 0, count: 8)
    private var meterClip = [Bool](repeating: false, count: 8)
    private var meterClipAge = [Int](repeating: 0, count: 8)
    /// LEDs Logic wants flashing; the bridge toggles them from `tick()`, as Pro Tools did.
    private var flashing = Set<Button>()
    private var flashOn = true
    private var ticks = 0
    /// Logic's seven-segment characters: timecode positions 0–9 (right to left), assignment 10–11.
    private var sevenSegment = [Character](repeating: " ", count: 12)
    /// Logic's LCD: two lines of 56 characters, 7 per strip. The desk shows 4 per strip.
    private var lcd = [UInt8](repeating: 0x20, count: 112)
    /// What each desk display currently shows, so unchanged text is not resent.
    private var displayShown: [Int: SurfaceCommand] = [:]
    /// Bumped whenever a strip's display changes; a revert only applies if it still matches.
    private var displayToken = [Int](repeating: 0, count: 10)
    /// In the wide time display, the assignment name is on display 9 until its revert.
    private var assignmentShowing = false

    /// A name too long for its display, moving across it.
    private struct Scroll {
        var text: [Character]
        var offset = 0
        var wait = Bridge.scrollHoldTicks
        var finished = false
        /// A value is on the display; the name waits for the revert.
        var paused = false

        var window: String { String(text[offset..<(offset + 4)]) }
        var atEnd: Bool { offset + 4 >= text.count }
    }
    private var scrolls: [Int: Scroll] = [:]

    public init(config: BridgeConfig = .default) {
        self.config = config
        buttonMap = Self.makeButtonMap(config)
        shiftButtonMap = Self.makeShiftButtonMap(config)
        buttonsForNote = Self.makeButtonsForNote(buttonMap, shiftButtonMap, config)
        navMode = config.nudgeModeAtStart ? .channel : .bank
        meterMode = config.meterModeAtStart
    }

    /// A strip showing a value that should go back to its name after a short time. The
    /// caller waits, then passes it to `revertDisplay`.
    public struct DisplayRevert: Equatable {
        public let strip: Int
        public let token: Int
    }

    public struct Output: Equatable {
        public var toLogic: [MCUMessage] = []
        public var toSurface: [SurfaceCommand] = []
        public var displayReverts: [DisplayRevert] = []
    }

    /// Commands to send once the desk is awake: the nav mode LEDs, plus every LED, ring,
    /// display and fader position Logic has sent so far (the desk drops messages until it
    /// is awake).
    public func startup() -> [SurfaceCommand] {
        // The desk keeps whatever it last showed, so everything Logic has not yet set is
        // cleared rather than left over from an earlier session.
        var commands = navModeLEDs() + [.led(Self.meterButton, on: meterMode)]
        let modeButtons: Set<Button> = [Self.bankButton, Self.nudgeButton, Self.meterButton]
        for button in Button.ledButtons.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) })
        where !modeButtons.contains(button) {
            commands.append(.led(button, on: ledState[button] ?? false))
        }
        for channel in logicFaderSeen.sorted() {
            commands.append(.fader(channel: channel, position: deskPosition[channel]))
        }
        for channel in 0..<8 {
            commands.append(.ring(channel: channel, currentRing(channel)))
        }
        for strip in 0...Self.positionStrip {
            commands.append(displayShown[strip] ?? .display(strip: strip, text: "", inverse: false))
        }
        return commands
    }

    /// Called every `tickSeconds`: lets meter peaks fall, clears old clips and toggles
    /// flashing LEDs.
    public mutating func tick() -> [SurfaceCommand] {
        var out = Output()
        ticks += 1
        if meterMode {
            for channel in 0..<8 {
                meterPeakAge[channel] += 1
                if meterPeakAge[channel] >= Self.peakHoldTicks, meterPeak[channel] > meterLevel[channel] {
                    meterPeak[channel] -= 1
                }
                if meterClip[channel] {
                    meterClipAge[channel] += 1
                    if meterClipAge[channel] >= Self.clipHoldTicks { meterClip[channel] = false }
                }
                updateRing(channel, into: &out)
            }
        }
        if ticks % Self.flashHalfPeriodTicks == 0, !flashing.isEmpty {
            flashOn.toggle()
            for button in flashing.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
                out.toSurface.append(.led(button, on: flashOn))
            }
        }
        for strip in scrolls.keys.sorted() { advanceScroll(strip, into: &out) }
        return out.toSurface
    }

    private mutating func advanceScroll(_ strip: Int, into out: inout Output) {
        guard var scroll = scrolls[strip], !scroll.paused, !scroll.finished else { return }
        scroll.wait -= 1
        guard scroll.wait <= 0 else { scrolls[strip] = scroll; return }
        if scroll.atEnd {
            switch config.nameScroll {
            case .always:
                scroll.offset = 0
                scroll.wait = Self.scrollHoldTicks
            default:
                scroll.finished = true
                scrolls[strip] = scroll
                show(strip, text: lcdText(strip: strip, line: 0), inverse: false, into: &out)
                return
            }
        } else {
            scroll.offset += 1
            scroll.wait = scroll.atEnd ? Self.scrollHoldTicks : Self.scrollStepTicks
        }
        scrolls[strip] = scroll
        show(strip, text: scroll.window, inverse: false, into: &out)
    }

    public mutating func fromSurface(_ event: SurfaceEvent) -> Output {
        var out = Output()
        switch event {
        case let .fader(channel, position):
            deskPosition[channel] = position
            out.toLogic.append(.fader(channel: channel, value: position << 4))
        case let .faderTouch(channel, isTouched):
            if isTouched {
                touched.insert(channel)
            } else {
                touched.remove(channel)
                out.toSurface.append(.fader(channel: channel, position: deskPosition[channel]))
            }
            out.toLogic.append(.faderTouch(channel: channel, touched: isTouched))
        case let .button(button, pressed):
            handleButton(button, pressed: pressed, into: &out)
        case let .encoder(channel, steps):
            out.toLogic.append(.vpot(channel: channel, steps: steps))
        }
        return out
    }

    private mutating func handleButton(_ button: Button, pressed: Bool, into out: inout Output) {
        if pressed {
            switch button {
            case Self.bankButton, Self.nudgeButton:
                navMode = button == Self.bankButton ? .bank : .channel
                out.toSurface += navModeLEDs()
                return
            case Self.recButton:
                recHeld = true
                return
            case Self.meterButton:
                meterMode.toggle()
                out.toSurface.append(.led(Self.meterButton, on: meterMode))
                for channel in 0..<8 { updateRing(channel, into: &out) }
                return
            case Self.rtzButton:
                // MCU has no return-to-zero; Logic goes to the start when Stop is pressed
                // while stopped, so RTZ is Stop twice. The release sends the second Stop's off.
                out.toLogic += [.note(.stop, on: true), .note(.stop, on: false), .note(.stop, on: true)]
                heldNotes[button] = .stop
                return
            default:
                break
            }
            if shiftHeld, let alternate = shiftButtonMap[button] {
                // The alternate is its own function, not Shift plus the usual one, so Logic
                // sees it without Shift. Shift is put back for whatever is pressed next.
                heldNotes[button] = alternate
                out.toLogic += [.note(.shift, on: false), .note(alternate, on: true), .note(.shift, on: true)]
                return
            }
            guard let note = note(for: button) else { return }
            if note == .shift { shiftHeld = true }
            heldNotes[button] = note
            out.toLogic.append(.note(note, on: true))
        } else {
            if button == Self.recButton { recHeld = false }
            if let note = heldNotes.removeValue(forKey: button) {
                if note == .shift { shiftHeld = false }
                out.toLogic.append(.note(note, on: false))
            }
        }
    }

    /// The MCU note a press of `button` sends right now, given the current modes.
    private func note(for button: Button) -> MCUNote? {
        if recHeld, button.row == Button.select(0).row, let channel = button.channel {
            return .recArm(channel)
        }
        if button == Self.leftButton || button == Self.rightButton {
            let left = button == Self.leftButton
            if logicZoomOn { return left ? .left : .right }
            switch navMode {
            case .bank: return left ? .bankLeft : .bankRight
            case .channel: return left ? .channelLeft : .channelRight
            }
        }
        return buttonMap[button]
    }

    private func navModeLEDs() -> [SurfaceCommand] {
        [.led(Self.bankButton, on: navMode == .bank), .led(Self.nudgeButton, on: navMode == .channel)]
    }

    public mutating func fromLogic(_ message: MCUMessage) -> Output {
        var out = Output()
        switch message {
        case let .fader(channel, value):
            let position = value >> 4
            deskPosition[channel] = position
            logicFaderSeen.insert(channel)
            // Never drive a motor against a hand on the fader.
            if !touched.contains(channel) {
                out.toSurface.append(.fader(channel: channel, position: position))
            }
        case let .note(note, on):
            if note == .zoom { logicZoomOn = on }
            for button in buttonsForNote[note] ?? [] where Button.ledButtons.contains(button) {
                ledState[button] = on
                flashing.remove(button)
                out.toSurface.append(.led(button, on: on))
            }
            if on, let name = Self.assignmentNames[note] {
                show(Self.assignmentStrip, text: name, inverse: false, into: &out)
                if config.timeDisplay == .wide {
                    // Display 9 belongs to the time; the assignment shows for a moment.
                    assignmentShowing = true
                    displayToken[Self.assignmentStrip] += 1
                    out.displayReverts.append(DisplayRevert(strip: Self.assignmentStrip, token: displayToken[Self.assignmentStrip]))
                }
            }
        case let .ledFlash(note):
            for button in buttonsForNote[note] ?? [] where Button.ledButtons.contains(button) {
                ledState[button] = true
                flashing.insert(button)
                out.toSurface.append(.led(button, on: flashOn))
            }
        case let .vpotRing(channel, centre, mode, position):
            ringState[channel] = Self.ring(centre: centre, mode: mode, position: position)
            updateRing(channel, into: &out)
        case let .meter(channel, level):
            guard channel < 8 else { break }
            switch level {
            case 0xE:
                meterClip[channel] = true
                meterClipAge[channel] = 0
            case 0xF:
                meterClip[channel] = false
            default:
                meterLevel[channel] = level
                if level >= meterPeak[channel] {
                    meterPeak[channel] = level
                    meterPeakAge[channel] = 0
                }
            }
            updateRing(channel, into: &out)
        case let .sevenSegment(position, character, _):
            guard position < sevenSegment.count else { break }
            sevenSegment[position] = character
            if position < 10 { showTime(into: &out) }
        case let .lcd(offset, text):
            updateLCD(offset: offset, text: text, into: &out)
        case .faderTouch, .vpot, .deviceQuery, .connectionQuery, .hostConnectionReply, .connectionConfirmation,
             .versionRequest, .versionReply:
            break    // the handshake is handled by the service
        }
        return out
    }

    // MARK: Rings

    private func currentRing(_ channel: Int) -> Ring {
        if meterMode {
            return Self.meterRing(level: meterLevel[channel], peak: meterPeak[channel], clip: meterClip[channel])
        }
        return ringState[channel] ?? .off
    }

    private mutating func updateRing(_ channel: Int, into out: inout Output) {
        let ring = currentRing(channel)
        guard ringShown[channel] != ring else { return }
        ringShown[channel] = ring
        out.toSurface.append(.ring(channel: channel, ring))
    }

    /// A meter the way Pro Tools drew one: a bar for the level, a dot holding the peak, and
    /// the 15th LED red after a clip. Logic's 12 levels are spread over the 14 LEDs.
    static func meterRing(level: Int, peak: Int, clip: Bool) -> Ring {
        var ring = Ring(lastRed: clip)
        let top = (min(level, 12) * 14 + 6) / 12
        if top > 0 { ring.light(1...top) }
        ring.light((min(peak, 12) * 14 + 6) / 12)
        return ring
    }

    /// Draws an MCU ring (11 LEDs, 6 in the centre) on the desk's 14-LED arc, whose
    /// centre falls between LEDs 7 and 8. The centre flag lights the 15th LED green.
    static func ring(centre: Bool, mode: VPotMode, position: Int) -> Ring {
        // Desk LED for each MCU position 1-11; position 6 is LEDs 7 and 8 together.
        let led = [0, 1, 2, 3, 5, 6, 7, 9, 10, 12, 13, 14]
        var ring = Ring(lastGreen: centre)
        let p = min(max(position, 0), 11)
        guard p > 0 else { return ring }
        switch mode {
        case .dot:
            ring.light(led[p])
            if p == 6 { ring.light(8) }
        case .boostCut:
            if p < 6 { ring.light(led[p]...7) } else if p > 6 { ring.light(8...led[p]) } else { ring.light(7...8) }
        case .wrap:
            ring.light(1...led[p])
        case .spread:
            ring.light(max(1, 8 - p)...min(14, 7 + p))
        }
        return ring
    }

    // MARK: Displays

    /// Logic's position as its four fields, left to right: bars, beats, subdivision and
    /// ticks, or hours, minutes, seconds and frames. Both are 3, 2, 2 and 3 characters.
    private func timeFields() -> [String] {
        let chars = Array(sevenSegment[0..<10].reversed())
        return [chars[0..<3], chars[3..<5], chars[5..<7], chars[7..<10]].map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }

    /// "a.b" right-aligned in 4 characters, or "ab" when the dot would not fit.
    static func timePair(_ a: String, _ b: String) -> String {
        if a.isEmpty && b.isEmpty { return "" }
        let joined = b.isEmpty ? a : a.count + b.count < 4 ? a + "." + b : a + b
        return String(repeating: " ", count: max(0, 4 - joined.count)) + joined.suffix(4)
    }

    private mutating func showTime(into out: inout Output) {
        let f = timeFields()
        switch config.timeDisplay {
        case .bars:
            show(Self.positionStrip, text: Self.timePair(f[0], ""), inverse: false, into: &out)
        case .barsBeats:
            show(Self.positionStrip, text: Self.timePair(f[0], f[1]), inverse: false, into: &out)
        case .wide:
            if !assignmentShowing {
                show(Self.assignmentStrip, text: Self.timePair(f[0], ""), inverse: false, into: &out)
            }
            show(Self.positionStrip, text: Self.timePair(f[1], f[2]), inverse: false, into: &out)
        }
    }

    /// Strips whose text changed get the track name (top line); a strip whose value
    /// (bottom line) changed on its own shows the value until the caller reverts it.
    private mutating func updateLCD(offset: Int, text: [UInt8], into out: inout Output) {
        var nameChanged = Set<Int>(), valueChanged = Set<Int>()
        for (i, byte) in text.enumerated() {
            let index = offset + i
            guard index < lcd.count, lcd[index] != byte else { continue }
            lcd[index] = byte
            let strip = index % 56 / 7
            if index < 56 { nameChanged.insert(strip) } else { valueChanged.insert(strip) }
        }
        for strip in (nameChanged.union(valueChanged)).sorted() where strip < 8 {
            displayToken[strip] += 1
            let name = lcdText(strip: strip, line: 0)
            let value = lcdText(strip: strip, line: 1)
            if name.isEmpty {
                // Some Logic views only use the bottom line; then it is the text to show.
                scrolls[strip] = nil
                show(strip, text: value, inverse: false, into: &out)
            } else if valueChanged.contains(strip), !nameChanged.contains(strip), !value.isEmpty {
                scrolls[strip]?.paused = true
                show(strip, text: value, inverse: config.valuesInverse, into: &out)
                out.displayReverts.append(DisplayRevert(strip: strip, token: displayToken[strip]))
            } else {
                let full = fullName(strip: strip)
                if config.nameScroll != .off, full.count > 4 {
                    let scroll = Scroll(text: Array(full))
                    scrolls[strip] = scroll
                    show(strip, text: scroll.window, inverse: false, into: &out)
                } else {
                    scrolls[strip] = nil
                    show(strip, text: name, inverse: false, into: &out)
                }
            }
        }
    }

    /// Puts the track name back after a value was shown. Does nothing if the display has
    /// changed again since the revert was issued.
    public mutating func revertDisplay(_ revert: DisplayRevert) -> [SurfaceCommand] {
        guard revert.token == displayToken[revert.strip] else { return [] }
        var out = Output()
        if revert.strip == Self.assignmentStrip {
            assignmentShowing = false
            showTime(into: &out)
            return out.toSurface
        }
        let name = lcdText(strip: revert.strip, line: 0)
        if var scroll = scrolls[revert.strip], !name.isEmpty {
            scroll.paused = false
            scrolls[revert.strip] = scroll
            show(revert.strip, text: scroll.finished ? name : scroll.window, inverse: false, into: &out)
            return out.toSurface
        }
        show(revert.strip, text: name.isEmpty ? lcdText(strip: revert.strip, line: 1) : name, inverse: false, into: &out)
        return out.toSurface
    }

    /// The strip's whole top line with the padding removed, for scrolling.
    private func fullName(strip: Int) -> String {
        let start = strip * 7
        return String(lcd[start..<(start + 7)].map { Character(UnicodeScalar($0)) })
            .trimmingCharacters(in: .whitespaces)
    }

    /// The strip's 7 LCD characters squeezed into the desk's 4. Names are abbreviated the
    /// way Pro Tools did it, or just cut, per the config; values (line 1) only lose their
    /// spaces, so "-10.5" is not turned into "-105".
    private func lcdText(strip: Int, line: Int) -> String {
        let start = line * 56 + strip * 7
        let text = String(lcd[start..<(start + 7)].map { Character(UnicodeScalar($0)) })
        if line == 0 {
            switch config.nameStyle {
            case .proTools: return Self.abbreviate(text, to: 4)
            case .plain: return String(String(text.prefix(4)).reversed().drop { $0 == " " }.reversed())
            }
        }
        return String(text.filter { $0 != " " }.prefix(4))
    }

    /// Shortens a name to `length` characters the way the Pro Tools 002 code does: it drops
    /// non-ASCII characters, then spaces, then lowercase vowels, then `, # - .`, then other
    /// lowercase letters, each pass working from the end and stopping as soon as the name
    /// fits. The first character is always kept. "Audio 1" becomes "Aud1", "Master" "Mstr".
    static func abbreviate(_ name: String, to length: Int) -> String {
        var chars = name.unicodeScalars.filter { $0.isASCII }.map { Character($0) }
        func drop(_ unwanted: (Character) -> Bool) {
            var i = chars.count - 1
            while chars.count > length && i >= 1 {
                if unwanted(chars[i]) { chars.remove(at: i) }
                i -= 1
            }
        }
        drop { $0 == " " }
        drop { "aeiou".contains($0) }
        drop { ",#-.".contains($0) }
        drop { $0.isLowercase }
        return String(chars.filter { $0 != " " }.prefix(length))
    }

    private mutating func show(_ strip: Int, text: String, inverse: Bool, into out: inout Output) {
        let command = SurfaceCommand.display(strip: strip, text: text, inverse: inverse)
        guard displayShown[strip] != command else { return }
        displayShown[strip] = command
        out.toSurface.append(command)
    }
}

extension Button {
    /// Buttons with a physical LED (docs/protocol.md, LEDs). Sending LED messages to the
    /// others is harmless but pointless.
    public static let ledButtons: Set<Button> = {
        let noLED: Set<String> = ["Shift", "Option", "Control", "Command", "Left", "Right", "Up", "Down",
                                  "F1", "F2", "F3", "F4", "F5", "RTZ", "Rewind", "Fast Forward",
                                  "Stop", "Play", "Record"]
        return Set(names.filter { !noLED.contains($0.value) }.keys)
            .union((0..<8).flatMap { [selectRed($0), recordReady($0)] })
    }()
}
