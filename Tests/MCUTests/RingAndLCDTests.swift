import Testing
@testable import MCU

@Test func vpotRingDecodesCentreModeAndPosition() {
    var decoder = MCUDecoder()
    #expect(decoder.decode([0xB0, 0x30, 0x06]) == [.vpotRing(channel: 0, centre: false, mode: .dot, position: 6)])
    #expect(decoder.decode([0xB0, 0x37, 0x5B]) == [.vpotRing(channel: 7, centre: true, mode: .boostCut, position: 11)])
    #expect(decoder.decode([0xB0, 0x32, 0x21]) == [.vpotRing(channel: 2, centre: false, mode: .wrap, position: 1)])
    #expect(decoder.decode([0xB0, 0x33, 0x30]) == [.vpotRing(channel: 3, centre: false, mode: .spread, position: 0)])
}

@Test func vpotRingRoundTrips() {
    var decoder = MCUDecoder()
    let message = MCUMessage.vpotRing(channel: 4, centre: true, mode: .spread, position: 9)
    #expect(decoder.decode(MCUEncoder.encode(message)) == [message])
}

@Test func lcdSysExCarriesOffsetAndText() {
    var decoder = MCUDecoder()
    // bridge-run-4.log: Logic writes the top line from offset 0.
    let bytes: [UInt8] = [0xF0, 0x00, 0x00, 0x66, 0x14, 0x12, 0x00, 0x41, 0x75, 0x64, 0x69, 0x6F, 0x20, 0x31, 0xF7]
    #expect(decoder.decode(bytes) == [.lcd(offset: 0, text: Array("Audio 1".utf8))])
    #expect(decoder.decode(MCUEncoder.encode(.lcd(offset: 0x38, text: [0x43]))) == [.lcd(offset: 56, text: [0x43])])
}

@Test func lcdSysExMaySpanPackets() {
    var decoder = MCUDecoder()
    #expect(decoder.decode([0xF0, 0x00, 0x00, 0x66, 0x14, 0x12, 0x07]) == [])
    #expect(decoder.decode([0x41, 0x42, 0xF7]) == [.lcd(offset: 7, text: [0x41, 0x42])])
    // A normal message straight after is still decoded.
    #expect(decoder.decode([0x90, 0x10, 0x7F]) == [.note(.mute(0), on: true)])
}

@Test func otherSysExAndUnknownCCsAreUnhandled() {
    var decoder = MCUDecoder()
    #expect(decoder.decode([0xF0, 0x00, 0x00, 0x66, 0x14, 0x00, 0xF7]) == [])
    #expect(decoder.decode([0xB0, 0x4C, 0x05]) == [])   // a CC Logic does not use
    // A status byte inside SysEx abandons it.
    #expect(decoder.decode([0xF0, 0x00, 0x00, 0x66, 0x90, 0x10, 0x00]) == [.note(.mute(0), on: false)])
}
