import Testing
import Digi00x
import MCU
@testable import BridgeCore

@Test func deskFaderBecomesFourteenBitPitchBend() {
    var bridge = Bridge()
    let out = bridge.fromSurface(.fader(channel: 0, position: 1023))
    #expect(out.toLogic == [.fader(channel: 0, value: 1023 << 4)])
    #expect(out.toSurface == [])
}

@Test func releaseSendsLastPositionBackToTheDesk() {
    var bridge = Bridge()
    _ = bridge.fromSurface(.faderTouch(channel: 2, touched: true))
    _ = bridge.fromSurface(.fader(channel: 2, position: 500))
    let out = bridge.fromSurface(.faderTouch(channel: 2, touched: false))
    #expect(out.toLogic == [.faderTouch(channel: 2, touched: false)])
    #expect(out.toSurface == [.fader(channel: 2, position: 500)])
}

@Test func logicFaderMovesMotorOnlyWhenUntouched() {
    var bridge = Bridge()
    #expect(bridge.fromLogic(.fader(channel: 1, value: 0x2000)).toSurface == [.fader(channel: 1, position: 0x200)])
    _ = bridge.fromSurface(.faderTouch(channel: 1, touched: true))
    #expect(bridge.fromLogic(.fader(channel: 1, value: 0x3000)).toSurface == [])
}

@Test func stripButtonsAndLEDsMapBothWays() {
    var bridge = Bridge()
    #expect(bridge.fromSurface(.button(.mute(4), pressed: true)).toLogic == [.note(.mute(4), on: true)])
    #expect(bridge.fromLogic(.note(.mute(4), on: true)).toSurface == [.led(.mute(4), on: true)])
    #expect(bridge.fromLogic(.note(.select(7), on: false)).toSurface == [.led(.select(7), on: false)])
}

@Test func transportHasNoLEDs() {
    var bridge = Bridge()
    #expect(bridge.fromSurface(.button(Button.named("Play")!, pressed: true)).toLogic == [.note(.play, on: true)])
    #expect(bridge.fromLogic(.note(.play, on: true)).toSurface == [])
}

@Test func encoderStepsBecomeVPot() {
    var bridge = Bridge()
    #expect(bridge.fromSurface(.encoder(channel: 3, steps: -2)).toLogic == [.vpot(channel: 3, steps: -2)])
}

private func button(_ name: String) -> Button { Button.named(name)! }

@Test func everyMappedButtonExistsAndModifiersMap() {
    var bridge = Bridge()
    #expect(bridge.fromSurface(.button(button("Shift"), pressed: true)).toLogic == [.note(.shift, on: true)])
    #expect(bridge.fromSurface(.button(button("Esc"), pressed: true)).toLogic == [.note(.cancel, on: true)])
    #expect(bridge.fromSurface(.button(button("Page Right"), pressed: true)).toLogic == [.note(.bankRight, on: true)])
}

@Test func navArrowsFollowBankAndNudgeModes() {
    var bridge = Bridge()
    #expect(bridge.navMode == .bank)
    #expect(bridge.fromSurface(.button(button("Right"), pressed: true)).toLogic == [.note(.bankRight, on: true)])
    #expect(bridge.fromSurface(.button(button("Right"), pressed: false)).toLogic == [.note(.bankRight, on: false)])

    let modeChange = bridge.fromSurface(.button(button("Nudge"), pressed: true))
    #expect(modeChange.toLogic == [])
    #expect(modeChange.toSurface == [.led(button("Bank"), on: false), .led(button("Nudge"), on: true)])
    #expect(bridge.fromSurface(.button(button("Left"), pressed: true)).toLogic == [.note(.channelLeft, on: true)])
}

@Test func releaseGoesToTheNoteThatWasPressed() {
    var bridge = Bridge()
    _ = bridge.fromSurface(.button(button("Right"), pressed: true))          // bank right
    _ = bridge.fromSurface(.button(button("Nudge"), pressed: true))          // mode changes while held
    #expect(bridge.fromSurface(.button(button("Right"), pressed: false)).toLogic == [.note(.bankRight, on: false)])
}

@Test func logicZoomTurnsArrowsIntoCursorKeys() {
    var bridge = Bridge()
    _ = bridge.fromLogic(.note(.zoom, on: true))
    #expect(bridge.fromSurface(.button(button("Left"), pressed: true)).toLogic == [.note(.left, on: true)])
    #expect(bridge.fromSurface(.button(button("Up"), pressed: true)).toLogic == [.note(.up, on: true)])
}

@Test func holdingRecTurnsSelectIntoRecordArm() {
    var bridge = Bridge()
    #expect(bridge.fromSurface(.button(button("Rec (meter)"), pressed: true)).toLogic == [])
    #expect(bridge.fromSurface(.button(.select(2), pressed: true)).toLogic == [.note(.recArm(2), on: true)])
    #expect(bridge.fromSurface(.button(.select(2), pressed: false)).toLogic == [.note(.recArm(2), on: false)])
    _ = bridge.fromSurface(.button(button("Rec (meter)"), pressed: false))
    #expect(bridge.fromSurface(.button(.select(2), pressed: true)).toLogic == [.note(.select(2), on: true)])
}

@Test func sharedNoteLightsEveryButtonMappedToIt() {
    var bridge = Bridge()
    let leds = bridge.fromLogic(.note(.assignPlugin, on: true)).toSurface
    #expect(Set(leds) == [.led(button("Insert"), on: true), .led(button("Insert (console view)"), on: true),
                          .display(strip: 8, text: "Plug", inverse: false)])
}

@Test func startupReplaysLogicStateAndNavMode() {
    var bridge = Bridge()
    _ = bridge.fromLogic(.note(.mute(1), on: true))
    _ = bridge.fromLogic(.fader(channel: 4, value: 0x2000))
    let commands = bridge.startup()
    #expect(commands.contains(.led(button("Bank"), on: true)))
    #expect(commands.contains(.led(.mute(1), on: true)))
    #expect(commands.contains(.fader(channel: 4, position: 0x200)))
    // Everything Logic has not set is cleared, so nothing is left over on the desk.
    #expect(commands.contains(.led(.mute(0), on: false)))
    #expect(commands.contains(.led(button("Undo"), on: false)))
    #expect(commands.contains(.ring(channel: 0, .off)))
    #expect(commands.contains(.display(strip: 0, text: "", inverse: false)))
    #expect(commands.contains(.display(strip: 9, text: "", inverse: false)))
    #expect(!commands.contains(.led(button("Nudge"), on: true)))
}

@Test func recordArmLightsRecordReadyLED() {
    var bridge = Bridge()
    // small-led-channels.log: row 04 is the small Record Ready LED above each SEL.
    #expect(bridge.fromLogic(.note(.recArm(3), on: true)).toSurface == [.led(.recordReady(3), on: true)])
    #expect(bridge.startup().contains(.led(.recordReady(3), on: true)))
    #expect(SurfaceEncoder.encode(.led(.recordReady(7), on: true)) == [0x90, 0x04, 0x47])
    // sel-colours.log: row 01 is the red element of the SEL LED.
    #expect(SurfaceEncoder.encode(.led(.selectRed(7), on: true)) == [0x90, 0x01, 0x47])
}
