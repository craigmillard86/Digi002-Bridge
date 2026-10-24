import Testing
import Digi00x
import MCU
@testable import BridgeCore

private func leds(_ ring: Ring) -> [Int] { (1...14).filter { ring.leds & (1 << ($0 - 1)) != 0 } }

@Test func ringModesMapElevenPositionsOntoFourteenLEDs() {
    #expect(leds(Bridge.ring(centre: false, mode: .dot, position: 1)) == [1])
    #expect(leds(Bridge.ring(centre: false, mode: .dot, position: 6)) == [7, 8])
    #expect(leds(Bridge.ring(centre: false, mode: .dot, position: 11)) == [14])
    #expect(leds(Bridge.ring(centre: false, mode: .boostCut, position: 3)) == [3, 4, 5, 6, 7])
    #expect(leds(Bridge.ring(centre: false, mode: .boostCut, position: 6)) == [7, 8])
    #expect(leds(Bridge.ring(centre: false, mode: .boostCut, position: 9)) == [8, 9, 10, 11, 12])
    #expect(leds(Bridge.ring(centre: false, mode: .wrap, position: 4)) == [1, 2, 3, 4, 5])
    #expect(leds(Bridge.ring(centre: false, mode: .spread, position: 1)) == [7, 8])
    #expect(leds(Bridge.ring(centre: false, mode: .spread, position: 11)) == Array(1...14))
    #expect(Bridge.ring(centre: false, mode: .wrap, position: 0) == .off)
    #expect(Bridge.ring(centre: true, mode: .dot, position: 0) == Ring(lastGreen: true))
}

@Test func logicRingGoesToTheDeskAndIsReplayed() {
    var bridge = Bridge()
    let out = bridge.fromLogic(.vpotRing(channel: 2, centre: false, mode: .wrap, position: 2))
    var expected = Ring()
    expected.light(1...2)
    #expect(out.toSurface == [.ring(channel: 2, expected)])
    #expect(bridge.startup().contains(.ring(channel: 2, expected)))
}

private func lcd(_ offset: Int, _ text: String) -> MCUMessage { .lcd(offset: offset, text: Array(text.utf8)) }

@Test func trackNamesAreSqueezedToFourCharacters() {
    var bridge = Bridge()
    let out = bridge.fromLogic(lcd(0, "Audio 1Inst 12 Vox    "))
    #expect(out.toSurface == [.display(strip: 0, text: "Aud1", inverse: false),
                              .display(strip: 1, text: "In12", inverse: false),
                              .display(strip: 2, text: "Vox", inverse: false)])
    #expect(out.displayReverts == [])
    // The same text again sends nothing.
    #expect(bridge.fromLogic(lcd(0, "Audio 1")).toSurface == [])
}

@Test func changedValueShowsInverseThenRevertsToTheName() {
    var bridge = Bridge()
    _ = bridge.fromLogic(lcd(0, "Audio 1"))
    _ = bridge.fromLogic(lcd(56, "  C    "))      // the initial value arrives with the name
    let out = bridge.fromLogic(lcd(56, " L23   "))
    #expect(out.toSurface == [.display(strip: 0, text: "L23", inverse: false)])
    #expect(out.displayReverts.count == 1)
    #expect(bridge.revertDisplay(out.displayReverts[0]) == [.display(strip: 0, text: "Aud1", inverse: false)])
    // A revert for a display that has since changed does nothing.
    let newer = bridge.fromLogic(lcd(56, " R10   "))
    _ = bridge.fromLogic(lcd(56, " R12   "))
    #expect(bridge.revertDisplay(newer.displayReverts[0]) == [])
}

@Test func bottomLineAloneIsShownAsPlainText() {
    var bridge = Bridge()
    // bridge-run-5.log: Logic's plug-in view wrote only the bottom line.
    let out = bridge.fromLogic(lcd(56, "Freq   Gain   "))
    #expect(out.toSurface == [.display(strip: 0, text: "Freq", inverse: false),
                              .display(strip: 1, text: "Gain", inverse: false)])
    #expect(out.displayReverts == [])
}

@Test func nameAndValueChangingTogetherShowsTheName() {
    var bridge = Bridge()
    _ = bridge.fromLogic(lcd(0, "Audio 1"))
    let out = bridge.fromLogic(.lcd(offset: 0, text: Array("Drums  ".utf8) + Array(repeating: 0x20, count: 49) + Array(" L5    ".utf8)))
    #expect(out.toSurface == [.display(strip: 0, text: "Drms", inverse: false)])
    #expect(out.displayReverts == [])
}

@Test func namesAreAbbreviatedLikeProTools() {
    // Passes read from the Digi002 bundle (reference/protools-10.3.10): spaces, lowercase
    // vowels, punctuation, lowercase letters, each from the end until the name fits.
    #expect(Bridge.abbreviate("Audio 1", to: 4) == "Aud1")
    #expect(Bridge.abbreviate("Master", to: 4) == "Mstr")
    #expect(Bridge.abbreviate("St Out", to: 4) == "StOt")
    #expect(Bridge.abbreviate("Inst 12", to: 4) == "In12")
    #expect(Bridge.abbreviate("Vox", to: 4) == "Vox")
    #expect(Bridge.abbreviate("Kick-In", to: 4) == "KckI")
    #expect(Bridge.abbreviate("ABCDEFG", to: 4) == "ABCD")
    #expect(Bridge.abbreviate("", to: 4) == "")
}

@Test func valuesKeepTheirPunctuation() {
    var bridge = Bridge()
    _ = bridge.fromLogic(lcd(0, "Audio 1"))
    _ = bridge.fromLogic(lcd(56, "  0.0  "))
    #expect(bridge.fromLogic(lcd(56, " -10.5 ")).toSurface == [.display(strip: 0, text: "-10.", inverse: false)])
}
