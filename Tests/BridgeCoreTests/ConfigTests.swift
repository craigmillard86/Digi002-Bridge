import Testing
import Digi00x
import Foundation
import MCU
@testable import BridgeCore

private func button(_ name: String) -> Button { Button.named(name)! }

@Test func defaultConfigGivesTheSpareButtonsTheirFunctions() {
    var bridge = Bridge()
    #expect(bridge.fromSurface(.button(button("A"), pressed: true)).toLogic == [.note(.marker, on: true)])
    #expect(bridge.fromSurface(.button(button("B"), pressed: true)).toLogic == [.note(.click, on: true)])
    #expect(bridge.fromSurface(.button(button("C"), pressed: true)).toLogic == [.note(.save, on: true)])
    #expect(bridge.fromSurface(.button(button("D"), pressed: true)).toLogic == [.note(.scrub, on: true)])
    #expect(bridge.fromSurface(.button(button("E"), pressed: true)).toLogic == [.note(.smpteBeats, on: true)])
    #expect(bridge.fromSurface(.button(button("Master Bypass"), pressed: true)).toLogic == [.note(.userA, on: true)])
    #expect(bridge.fromSurface(.button(button("Master Faders"), pressed: true)).toLogic == [.note(.globalView, on: true)])
    // Logic's state for the function lights the desk button.
    #expect(bridge.fromLogic(.note(.click, on: true)).toSurface == [.led(button("B"), on: true)])
    #expect(bridge.fromLogic(.note(.globalView, on: true)).toSurface == [.led(button("Master Faders"), on: true)])
}

@Test func configuredButtonsFollowTheConfig() {
    var config = BridgeConfig()
    config.buttons["A"] = .f6
    config.buttons["B"] = .none
    config.buttons["Master Faders"] = .assignTrack
    var bridge = Bridge(config: config)
    #expect(bridge.fromSurface(.button(button("A"), pressed: true)).toLogic == [.note(.function(6), on: true)])
    #expect(bridge.fromSurface(.button(button("B"), pressed: true)).toLogic == [])
    #expect(bridge.fromSurface(.button(button("B"), pressed: false)).toLogic == [])
    #expect(bridge.fromSurface(.button(button("Master Faders"), pressed: true)).toLogic == [.note(.assignTrack, on: true)])
    // F6 now lights both the Mix button and A.
    let lit = bridge.fromLogic(.note(.function(6), on: true)).toSurface
    #expect(lit.contains(.led(button("A"), on: true)))
    #expect(lit.contains(.led(button("Mix"), on: true)))
    // The fixed buttons are untouched by the config.
    #expect(bridge.fromSurface(.button(button("Play"), pressed: true)).toLogic == [.note(.play, on: true)])
}

@Test func everyActionHasANoteExceptNone() {
    for action in ButtonAction.allCases {
        #expect((action.note == nil) == (action == .none), "\(action)")
        #expect(!action.title.isEmpty)
    }
}

@Test func startModesComeFromTheConfig() {
    var config = BridgeConfig()
    config.nudgeModeAtStart = true
    config.meterModeAtStart = true
    let bridge = Bridge(config: config)
    #expect(bridge.navMode == .channel)
    #expect(bridge.meterMode)
    let startup = bridge.startup()
    #expect(startup.contains(.led(Bridge.nudgeButton, on: true)))
    #expect(startup.contains(.led(Bridge.bankButton, on: false)))
    #expect(startup.contains(.led(Bridge.meterButton, on: true)))
}

@Test func armedTrackCanLightSelectRed() {
    var config = BridgeConfig()
    config.armedSelectRed = true
    var bridge = Bridge(config: config)
    let out = bridge.fromLogic(.note(.recArm(2), on: true)).toSurface
    #expect(out == [.led(.recordReady(2), on: true), .led(.selectRed(2), on: true)])
    #expect(Bridge().fromLogicCopy(.note(.recArm(2), on: true)) == [.led(.recordReady(2), on: true)])
}

private extension Bridge {
    func fromLogicCopy(_ message: MCUMessage) -> [SurfaceCommand] {
        var copy = self
        return copy.fromLogic(message).toSurface
    }
}

@Test func plainNameStyleCutsInsteadOfAbbreviating() {
    var config = BridgeConfig()
    config.nameStyle = .plain
    config.valuesInverse = true
    var bridge = Bridge(config: config)
    let out = bridge.fromLogic(.lcd(offset: 0, text: Array("Audio 1Vox    ".utf8)))
    #expect(out.toSurface == [.display(strip: 0, text: "Audi", inverse: false),
                              .display(strip: 1, text: "Vox", inverse: false)])
    // A changed value alone shows inverse when asked.
    let value = bridge.fromLogic(.lcd(offset: 56, text: Array("-10.5  ".utf8)))
    #expect(value.toSurface == [.display(strip: 0, text: "-10.", inverse: true)])
}

@Test func configRoundTripsThroughJSONAndToleratesPartialFiles() throws {
    var config = BridgeConfig()
    config.buttons["E"] = .userB
    config.deskWakeSeconds = 7
    config.hostBundleID = "com.example.daw"
    let data = try config.json()
    #expect(try BridgeConfig.from(json: data) == config)

    // Unknown keys, unknown buttons and bad action names are ignored; missing keys default.
    let partial = """
        {"buttons": {"A": "click", "Z": "save", "B": "nonsense"}, "valueDisplaySeconds": 99, "colour": "blue"}
        """
    let loaded = try BridgeConfig.from(json: Data(partial.utf8))
    #expect(loaded.buttons["A"] == .click)
    #expect(loaded.buttons["B"] == .click)        // the default, since "nonsense" is not an action
    #expect(loaded.buttons["Z"] == nil)
    #expect(loaded.valueDisplaySeconds == 10)      // clamped
    #expect(loaded.deskWakeSeconds == 5)
    #expect(loaded.nameStyle == .proTools)
    #expect(try BridgeConfig.from(json: Data("{}".utf8)) == .default)
}
