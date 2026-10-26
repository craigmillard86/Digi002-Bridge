import Digi00x
import Foundation
import MCU

/// A Mackie Control function a desk button can be given in the config. The raw value is
/// the name used in the config file; `title` is what the settings window shows.
public enum ButtonAction: String, CaseIterable, Codable {
    case none
    case marker, nudge, click, save, scrub, globalView, smpteBeats
    case userA, userB
    case f1, f2, f3, f4, f5, f6, f7, f8
    case assignTrack, assignPan, assignSend, assignPlugin, assignEQ, assignInstrument
    case bankLeft, bankRight, channelLeft, channelRight, flip, zoom
    case nameValue, enter, undo, cancel
    case shift, option, control, command
    case cycle, drop, replace
    case rewind, fastForward, stop, play, record
    case up, down, left, right

    /// The note sent to Logic, or nil for `none`.
    public var note: MCUNote? {
        switch self {
        case .none: return nil
        case .marker: return .marker
        case .nudge: return .nudge
        case .click: return .click
        case .save: return .save
        case .scrub: return .scrub
        case .globalView: return .globalView
        case .smpteBeats: return .smpteBeats
        case .userA: return .userA
        case .userB: return .userB
        case .f1: return .function(1)
        case .f2: return .function(2)
        case .f3: return .function(3)
        case .f4: return .function(4)
        case .f5: return .function(5)
        case .f6: return .function(6)
        case .f7: return .function(7)
        case .f8: return .function(8)
        case .assignTrack: return .assignTrack
        case .assignPan: return .assignPan
        case .assignSend: return .assignSend
        case .assignPlugin: return .assignPlugin
        case .assignEQ: return .assignEQ
        case .assignInstrument: return .assignInstrument
        case .bankLeft: return .bankLeft
        case .bankRight: return .bankRight
        case .channelLeft: return .channelLeft
        case .channelRight: return .channelRight
        case .flip: return .flip
        case .zoom: return .zoom
        case .nameValue: return .nameValue
        case .enter: return .enter
        case .undo: return .undo
        case .cancel: return .cancel
        case .shift: return .shift
        case .option: return .option
        case .control: return .control
        case .command: return .command
        case .cycle: return .cycle
        case .drop: return .drop
        case .replace: return .replace
        case .rewind: return .rewind
        case .fastForward: return .fastForward
        case .stop: return .stop
        case .play: return .play
        case .record: return .record
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }

    /// What the function does in Logic, in the words of Logic's control surface guide.
    public var title: String {
        switch self {
        case .none: return "Nothing"
        case .marker: return "Marker (hold for marker mode; with Shift creates a marker)"
        case .nudge: return "Nudge mode (arrows nudge the selection)"
        case .click: return "Metronome on/off"
        case .save: return "Save project"
        case .scrub: return "Scrub mode"
        case .globalView: return "Global view (all tracks / mixer view)"
        case .smpteBeats: return "Position display: SMPTE or bars/beats"
        case .userA: return "User switch A (assign it in Logic's Controller Assignments)"
        case .userB: return "User switch B (assign it in Logic's Controller Assignments)"
        case .f1: return "F1 (screenset 1)"
        case .f2: return "F2 (screenset 2)"
        case .f3: return "F3 (screenset 3)"
        case .f4: return "F4 (screenset 4)"
        case .f5: return "F5 (screenset 5)"
        case .f6: return "F6 (screenset 6)"
        case .f7: return "F7 (screenset 7)"
        case .f8: return "F8 (screenset 8)"
        case .assignTrack: return "Encoders: track parameters"
        case .assignPan: return "Encoders: pan"
        case .assignSend: return "Encoders: sends"
        case .assignPlugin: return "Encoders: plug-in"
        case .assignEQ: return "Encoders: EQ"
        case .assignInstrument: return "Encoders: instrument"
        case .bankLeft: return "Bank left (8 tracks)"
        case .bankRight: return "Bank right (8 tracks)"
        case .channelLeft: return "Channel left (1 track)"
        case .channelRight: return "Channel right (1 track)"
        case .flip: return "Flip faders and encoders"
        case .zoom: return "Zoom mode"
        case .nameValue: return "Display names or values"
        case .enter: return "Enter"
        case .undo: return "Undo"
        case .cancel: return "Cancel / Esc"
        case .shift: return "Shift modifier"
        case .option: return "Option modifier"
        case .control: return "Control modifier"
        case .command: return "Command modifier"
        case .cycle: return "Cycle on/off"
        case .drop: return "Autopunch on/off"
        case .replace: return "Replace mode on/off"
        case .rewind: return "Rewind"
        case .fastForward: return "Fast forward"
        case .stop: return "Stop"
        case .play: return "Play"
        case .record: return "Record"
        case .up: return "Cursor up"
        case .down: return "Cursor down"
        case .left: return "Cursor left"
        case .right: return "Cursor right"
        }
    }
}

/// Everything a user can change about the bridge. Stored as JSON (see `ConfigFile` in
/// BridgeRuntime); every key is optional and missing keys take the defaults here, so an
/// old or hand-written file keeps working.
public struct BridgeConfig: Equatable, Codable {
    /// How a track name is squeezed into the desk's 4 characters.
    public enum NameStyle: String, Codable, CaseIterable {
        /// Pro Tools' rule: drop spaces, vowels and punctuation from the end first ("Audio 1" is "Aud1").
        case proTools
        /// The first four characters ("Audio 1" is "Audi").
        case plain
    }

    /// What the right-hand displays make of Logic's position (bars/beats or SMPTE).
    public enum TimeDisplay: String, Codable, CaseIterable {
        /// Display 10 shows the bar number (or the hours); display 9 the encoder assignment.
        case bars
        /// Display 10 shows bar and beat as "12.3" (or hours and minutes); display 9 the assignment.
        case barsBeats
        /// Display 9 shows the bar (or hours), display 10 the beat and subdivision (or minutes
        /// and seconds); the assignment appears on display 9 for a moment when it changes.
        case wide
    }

    /// What happens to a track name longer than the display's 4 characters.
    public enum NameScroll: String, Codable, CaseIterable {
        /// It is shortened (see `NameStyle`).
        case off
        /// It scrolls through once when it appears, then settles on the short form.
        case once
        /// It keeps scrolling.
        case always
    }

    /// Desk buttons that have no fixed Mackie Control meaning and take their function
    /// from the config, in the order the settings window lists them.
    public static let configurableButtons = ["A", "B", "C", "D", "E", "Master Bypass", "Master Faders"]

    public static let defaultButtons: [String: ButtonAction] = [
        "A": .marker,
        "B": .click,
        "C": .save,
        "D": .scrub,
        "E": .smpteBeats,
        "Master Bypass": .userA,
        "Master Faders": .globalView,
    ]

    /// Function of each configurable button, by its name as printed on the desk.
    public var buttons = defaultButtons
    /// What each configurable button does while the desk's Shift is held. A button with no
    /// entry (or `none`) keeps its usual function, which Logic then sees with Shift held.
    public var shiftButtons: [String: ButtonAction] = [:]
    /// How track names are shortened.
    public var nameStyle = NameStyle.proTools
    /// Whether long names scroll.
    public var nameScroll = NameScroll.off
    /// How Logic's position is shown on the right-hand displays.
    public var timeDisplay = TimeDisplay.bars
    /// Show a changed value light-on-dark for the moment it is displayed.
    public var valuesInverse = false
    /// How long a changed value stays on a strip's display before the name returns.
    public var valueDisplaySeconds = 1.5
    /// Rings show Logic's meters rather than the V-Pots until Meter is pressed.
    public var meterModeAtStart = false
    /// Whether the nav pad's arrows start by moving the bank by 8 tracks (Bank) or 1 (Nudge).
    public var nudgeModeAtStart = false
    /// Light a record-armed track's SEL button red as well as its Record Ready LED.
    public var armedSelectRed = false
    /// How long to wait after connecting before the desk accepts commands.
    public var deskWakeSeconds = 5.0
    /// Run a silent audio stream on the desk while connected. Avid's driver only delivers
    /// MIDI to the desk while its audio engine runs; without this, Logic stopping its
    /// audio (quitting, changing device) leaves the driver stuck and the desk deaf.
    public var holdAudioEngine = true
    /// Reconnect the desk by itself when it has stopped taking commands, which the bridge
    /// notices from faders springing back after they are released (see `StuckDetector`).
    public var reconnectWhenStuck = true
    /// The application the desk is connected for, by bundle identifier.
    public var hostBundleID = "com.apple.logic10"

    public init() {}

    public static let `default` = BridgeConfig()

    /// The action for a configurable button; `none` for one not in the table.
    public func action(for buttonName: String) -> ButtonAction {
        buttons[buttonName] ?? .none
    }

    /// The action for a configurable button while Shift is held; `none` means its usual one.
    public func shiftAction(for buttonName: String) -> ButtonAction {
        shiftButtons[buttonName] ?? .none
    }

    enum CodingKeys: String, CodingKey {
        case buttons, shiftButtons, nameStyle, nameScroll, timeDisplay, valuesInverse, valueDisplaySeconds
        case meterModeAtStart, nudgeModeAtStart, armedSelectRed, deskWakeSeconds, holdAudioEngine, reconnectWhenStuck
        case hostBundleID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BridgeConfig()
        // Unknown button names and action names are dropped rather than failing the file.
        func actions(_ key: CodingKeys, over base: [String: ButtonAction]) throws -> [String: ButtonAction] {
            guard let raw = try c.decodeIfPresent([String: String].self, forKey: key) else { return base }
            var result = base
            for (name, action) in raw where Self.configurableButtons.contains(name) {
                if let action = ButtonAction(rawValue: action) { result[name] = action }
            }
            return result
        }
        buttons = try actions(.buttons, over: defaults.buttons)
        shiftButtons = try actions(.shiftButtons, over: [:]).filter { $0.value != .none }
        nameStyle = (try? c.decodeIfPresent(NameStyle.self, forKey: .nameStyle)) ?? nil ?? defaults.nameStyle
        nameScroll = (try? c.decodeIfPresent(NameScroll.self, forKey: .nameScroll)) ?? nil ?? defaults.nameScroll
        timeDisplay = (try? c.decodeIfPresent(TimeDisplay.self, forKey: .timeDisplay)) ?? nil ?? defaults.timeDisplay
        valuesInverse = try c.decodeIfPresent(Bool.self, forKey: .valuesInverse) ?? defaults.valuesInverse
        valueDisplaySeconds = try c.decodeIfPresent(Double.self, forKey: .valueDisplaySeconds) ?? defaults.valueDisplaySeconds
        meterModeAtStart = try c.decodeIfPresent(Bool.self, forKey: .meterModeAtStart) ?? defaults.meterModeAtStart
        nudgeModeAtStart = try c.decodeIfPresent(Bool.self, forKey: .nudgeModeAtStart) ?? defaults.nudgeModeAtStart
        armedSelectRed = try c.decodeIfPresent(Bool.self, forKey: .armedSelectRed) ?? defaults.armedSelectRed
        deskWakeSeconds = try c.decodeIfPresent(Double.self, forKey: .deskWakeSeconds) ?? defaults.deskWakeSeconds
        holdAudioEngine = try c.decodeIfPresent(Bool.self, forKey: .holdAudioEngine) ?? defaults.holdAudioEngine
        reconnectWhenStuck = try c.decodeIfPresent(Bool.self, forKey: .reconnectWhenStuck) ?? defaults.reconnectWhenStuck
        hostBundleID = try c.decodeIfPresent(String.self, forKey: .hostBundleID) ?? defaults.hostBundleID
        valueDisplaySeconds = min(max(valueDisplaySeconds, 0.2), 10)
        deskWakeSeconds = min(max(deskWakeSeconds, 1), 30)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(buttons.mapValues(\.rawValue), forKey: .buttons)
        try c.encode(shiftButtons.filter { $0.value != .none }.mapValues(\.rawValue), forKey: .shiftButtons)
        try c.encode(nameStyle, forKey: .nameStyle)
        try c.encode(nameScroll, forKey: .nameScroll)
        try c.encode(timeDisplay, forKey: .timeDisplay)
        try c.encode(valuesInverse, forKey: .valuesInverse)
        try c.encode(valueDisplaySeconds, forKey: .valueDisplaySeconds)
        try c.encode(meterModeAtStart, forKey: .meterModeAtStart)
        try c.encode(nudgeModeAtStart, forKey: .nudgeModeAtStart)
        try c.encode(armedSelectRed, forKey: .armedSelectRed)
        try c.encode(deskWakeSeconds, forKey: .deskWakeSeconds)
        try c.encode(holdAudioEngine, forKey: .holdAudioEngine)
        try c.encode(reconnectWhenStuck, forKey: .reconnectWhenStuck)
        try c.encode(hostBundleID, forKey: .hostBundleID)
    }

    /// The file as JSON, keys sorted, readable by hand.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func from(json data: Data) throws -> BridgeConfig {
        try JSONDecoder().decode(BridgeConfig.self, from: data)
    }
}
