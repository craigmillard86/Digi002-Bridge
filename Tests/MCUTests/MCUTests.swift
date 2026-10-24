import Testing
@testable import MCU

@Test func faderIsPitchBendPerChannel() {
    #expect(MCUEncoder.encode(.fader(channel: 0, value: 0x3FFF)) == [0xE0, 0x7F, 0x7F])
    #expect(MCUEncoder.encode(.fader(channel: 7, value: 0x2000)) == [0xE7, 0x00, 0x40])
}

@Test func touchAndButtonsAreNotes() {
    #expect(MCUEncoder.encode(.faderTouch(channel: 2, touched: true)) == [0x90, 0x6A, 0x7F])
    #expect(MCUEncoder.encode(.note(.mute(0), on: true)) == [0x90, 0x10, 0x7F])
    #expect(MCUEncoder.encode(.note(.play, on: false)) == [0x90, 0x5E, 0x00])
}

@Test func vpotIsSignAndMagnitude() {
    #expect(MCUEncoder.encode(.vpot(channel: 0, steps: 3)) == [0xB0, 0x10, 0x03])
    #expect(MCUEncoder.encode(.vpot(channel: 1, steps: -2)) == [0xB0, 0x11, 0x42])
}

@Test func decodesFaderFeedbackAndLEDs() {
    var decoder = MCUDecoder()
    #expect(decoder.decode([0xE3, 0x00, 0x40]) == [.fader(channel: 3, value: 0x2000)])
    #expect(decoder.decode([0x90, 0x18, 0x7F, 0x18, 0x00]) ==
            [.note(.select(0), on: true), .note(.select(0), on: false)])
}

@Test func ignoresMasterFaderAndSysEx() {
    var decoder = MCUDecoder()
    #expect(decoder.decode([0xE8, 0x00, 0x40]) == [])
    #expect(decoder.decode([0xF0, 0x00, 0x00, 0x66, 0x14, 0x00, 0xF7]) == [])   // device query, not LCD text
    #expect(decoder.decode([0xE0, 0x7F, 0x7F]) == [.fader(channel: 0, value: 0x3FFF)])
}
