import Testing
import Digi00x
import Foundation
import MCU
@testable import BridgeCore

private func button(_ name: String) -> Button { Button.named(name)! }

/// Sends Logic's 10-character position display, left to right.
private func sendTime(_ bridge: inout Bridge, _ text: String) {
    for (i, ch) in text.enumerated() {
        _ = bridge.fromLogic(.sevenSegment(position: 9 - i, character: ch, dot: false))
    }
}

private func shown(_ strip: Int, _ text: String) -> SurfaceCommand { .display(strip: strip, text: text, inverse: false) }

@Test func shiftLayerGivesTheSpareButtonsASecondFunction() {
    var config = BridgeConfig()
    config.shiftButtons["A"] = .click
    var bridge = Bridge(config: config)
    // Without Shift, A is still the marker button.
    #expect(bridge.fromSurface(.button(button("A"), pressed: true)).toLogic == [.note(.marker, on: true)])
    #expect(bridge.fromSurface(.button(button("A"), pressed: false)).toLogic == [.note(.marker, on: false)])
    // With Shift held it sends its alternate on its own, and Shift is put back for the next button.
    _ = bridge.fromSurface(.button(button("Shift"), pressed: true))
    #expect(bridge.fromSurface(.button(button("A"), pressed: true)).toLogic
            == [.note(.shift, on: false), .note(.click, on: true), .note(.shift, on: true)])
    #expect(bridge.fromSurface(.button(button("A"), pressed: false)).toLogic == [.note(.click, on: false)])
    // B has no alternate: Shift+B is Shift plus its usual function, as before.
    #expect(bridge.fromSurface(.button(button("B"), pressed: true)).toLogic == [.note(.click, on: true)])
    _ = bridge.fromSurface(.button(button("Shift"), pressed: false))
    #expect(bridge.fromSurface(.button(button("A"), pressed: true)).toLogic == [.note(.marker, on: true)])
    // A lights for its main function only; a button whose only function is on Shift lights for that.
    config.buttons["C"] = .none
    config.shiftButtons["C"] = .cycle
    bridge = Bridge(config: config)
    #expect(bridge.fromLogic(.note(.click, on: true)).toSurface == [.led(button("B"), on: true)])
    #expect(bridge.fromLogic(.note(.cycle, on: true)).toSurface.contains(.led(button("C"), on: true)))
}

@Test func shiftLayerAndDisplayOptionsRoundTripThroughJSON() throws {
    var config = BridgeConfig()
    config.shiftButtons["A"] = .click
    config.timeDisplay = .wide
    config.nameScroll = .once
    let data = try config.json()
    #expect(try BridgeConfig.from(json: data) == config)
    #expect(String(decoding: data, as: UTF8.self).contains("\"shiftButtons\""))
    // A file without the new keys, or with a "none" alternate or an unknown button, reads as the defaults.
    let old = try BridgeConfig.from(json: Data("{\"shiftButtons\": {\"B\": \"none\", \"Zzz\": \"click\"}}".utf8))
    #expect(old.shiftButtons.isEmpty)
    #expect(old.timeDisplay == .bars)
    #expect(old.nameScroll == .off)
}

@Test func positionDisplayStyles() {
    // Logic's display is 3, 2, 2 and 3 characters: bars, beats, subdivision, ticks in
    // bars/beats; hours, minutes, seconds, frames in SMPTE.
    var bridge = Bridge()
    sendTime(&bridge, " 12 3 1  1")
    #expect(bridge.startup().contains(shown(9, "  12")))

    var config = BridgeConfig()
    config.timeDisplay = .barsBeats
    bridge = Bridge(config: config)
    sendTime(&bridge, " 12 3 1  1")
    #expect(bridge.startup().contains(shown(9, "12.3")))
    sendTime(&bridge, "123 4 1  1")
    #expect(bridge.startup().contains(shown(9, "1234")))   // no room for the dot
    sendTime(&bridge, "  10215 12")                        // 1:02:15:12 in SMPTE
    #expect(bridge.startup().contains(shown(9, "1.02")))

    config.timeDisplay = .wide
    bridge = Bridge(config: config)
    sendTime(&bridge, " 12 3 1  1")
    #expect(bridge.startup().contains(shown(8, "  12")))
    #expect(bridge.startup().contains(shown(9, " 3.1")))
    sendTime(&bridge, "  10215 12")
    #expect(bridge.startup().contains(shown(8, "   1")))
    #expect(bridge.startup().contains(shown(9, "0215")))
    // The assignment borrows display 9 until its revert; the time keeps moving underneath.
    let pan = bridge.fromLogic(.note(.assignPan, on: true))
    #expect(pan.toSurface.contains(shown(8, "Pan")))
    #expect(pan.displayReverts.count == 1)
    sendTime(&bridge, " 13 1 1  1")
    #expect(bridge.startup().contains(shown(8, "Pan")))
    #expect(bridge.revertDisplay(pan.displayReverts[0]) == [shown(8, "  13")])
}

@Test func longNamesScrollOnceThenSettle() {
    var config = BridgeConfig()
    config.nameScroll = .once
    var bridge = Bridge(config: config)
    #expect(bridge.fromLogic(.lcd(offset: 0, text: Array("Audio 1".utf8))).toSurface == [shown(0, "Audi")])
    // 1 s rest, two steps of 0.3 s, 1 s rest at the end, then the short name.
    var out: [SurfaceCommand] = []
    for _ in 0..<26 { out += bridge.tick() }
    #expect(out == [shown(0, "udio"), shown(0, "dio "), shown(0, "io 1"), shown(0, "Aud1")])
    #expect(bridge.tick() == [])
    // A short name does not scroll.
    #expect(bridge.fromLogic(.lcd(offset: 7, text: Array("Vox    ".utf8))).toSurface == [shown(1, "Vox")])
    for _ in 0..<30 { #expect(bridge.tick() == []) }
}

@Test func namesCanKeepScrollingAndWaitWhileAValueShows() {
    var config = BridgeConfig()
    config.nameScroll = .always
    var bridge = Bridge(config: config)
    _ = bridge.fromLogic(.lcd(offset: 0, text: Array("Audio 1".utf8)))
    var out: [SurfaceCommand] = []
    for _ in 0..<26 { out += bridge.tick() }
    #expect(out == [shown(0, "udio"), shown(0, "dio "), shown(0, "io 1"), shown(0, "Audi")])
    let value = bridge.fromLogic(.lcd(offset: 56, text: Array(" L23   ".utf8)))
    #expect(value.toSurface == [shown(0, "L23")])
    for _ in 0..<30 { #expect(bridge.tick() == []) }
    #expect(bridge.revertDisplay(value.displayReverts[0]) == [shown(0, "Audi")])
    out = []
    for _ in 0..<26 { out += bridge.tick() }
    #expect(out == [shown(0, "udio"), shown(0, "dio "), shown(0, "io 1"), shown(0, "Audi")])
}
