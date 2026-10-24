import Testing
@testable import Digi00x

// Byte sequences are copied from the logs in captures/ named in each test.

@Test func faderCoarseThenFineGivesTenBitPosition() {
    var decoder = SurfaceDecoder()
    // fader1-background.log: coarse and fine arrive as separate packets.
    #expect(decoder.decode([0xB0, 0x00, 0x2F]) == [])
    #expect(decoder.decode([0xB0, 0x20, 0x30]) == [.fader(channel: 0, position: 0x2F << 3 | 3)])
    // Full scale.
    _ = decoder.decode([0xB0, 0x00, 0x7F])
    #expect(decoder.decode([0xB0, 0x20, 0x70]) == [.fader(channel: 0, position: 1023)])
}

@Test func faderEightUsesControllersSevenAndThirtyNine() {
    var decoder = SurfaceDecoder()
    // fader1-background.log, the fader 8 sweep.
    #expect(decoder.decode([0xB0, 0x07, 0x40, 0xB0, 0x27, 0x50]) == [.fader(channel: 7, position: 0x40 << 3 | 5)])
}

@Test func faderTouchIsRowFiveColumnsZeroToSeven() {
    var decoder = SurfaceDecoder()
    // echo-test-2.log
    #expect(decoder.decode([0x90, 0x05, 0x41]) == [.faderTouch(channel: 1, touched: true)])
    #expect(decoder.decode([0x90, 0x05, 0x01]) == [.faderTouch(channel: 1, touched: false)])
    #expect(decoder.decode([0x90, 0x05, 0x47]) == [.faderTouch(channel: 7, touched: true)])
}

@Test func rowFiveOutsideTheStripsIsAButton() {
    var decoder = SurfaceDecoder()
    // round4-right.log: Quick Punch and arrow left share row 05 with fader touch.
    #expect(decoder.decode([0x90, 0x05, 0x4E]) == [.button(Button.named("Quick Punch")!, pressed: true)])
    #expect(decoder.decode([0x90, 0x05, 0x0D]) == [.button(Button.named("Left")!, pressed: false)])
}

@Test func stripButtonsDecodeByRowAndChannel() {
    var decoder = SurfaceDecoder()
    // round1-strips.log
    #expect(decoder.decode([0x90, 0x00, 0x40]) == [.button(.select(0), pressed: true)])
    #expect(decoder.decode([0x90, 0x02, 0x43]) == [.button(.solo(3), pressed: true)])
    #expect(decoder.decode([0x90, 0x03, 0x07]) == [.button(.mute(7), pressed: false)])
}

@Test func transportButtonsHaveNames() {
    var decoder = SurfaceDecoder()
    // round4-right.log
    #expect(decoder.decode([0x90, 0x0A, 0x4E]) == [.button(Button.named("Play")!, pressed: true)])
    #expect(Button(row: 0x09, column: 0x0E).description == "Stop")
}

@Test func encodersAreSignedStepsAroundSixtyFour() {
    var decoder = SurfaceDecoder()
    // round2-encoders.log
    #expect(decoder.decode([0xB0, 0x40, 0x41]) == [.encoder(channel: 0, steps: 1)])
    #expect(decoder.decode([0xB0, 0x47, 0x3E]) == [.encoder(channel: 7, steps: -2)])
}

@Test func runningStatusAndRealtimeBytesAreHandled() {
    var decoder = SurfaceDecoder()
    #expect(decoder.decode([0x90, 0x00, 0x40, 0xF8, 0x00, 0x00]) ==
            [.button(.select(0), pressed: true), .button(.select(0), pressed: false)])
}

@Test func faderCommandUsesRunningStatus() {
    // fader-probe-6.log: only this form moved the motor.
    #expect(SurfaceEncoder.encode(.fader(channel: 0, position: 1023)) == [0xB0, 0x00, 0x7F, 0x20, 0x70])
    #expect(SurfaceEncoder.encode(.fader(channel: 0, position: 0)) == [0xB0, 0x00, 0x00, 0x20, 0x00])
    #expect(SurfaceEncoder.encode(.fader(channel: 7, position: 1023)) == [0xB0, 0x07, 0x7F, 0x27, 0x70])
}

@Test func faderPositionRoundTrips() {
    var decoder = SurfaceDecoder()
    for position in stride(from: 0, through: 1023, by: 7) {
        #expect(decoder.decode(SurfaceEncoder.encode(.fader(channel: 2, position: position))) ==
                [.fader(channel: 2, position: position)])
    }
}

@Test func ledCommandMatchesButtonAddress() {
    // leds-1-strips.log
    #expect(SurfaceEncoder.encode(.led(.mute(0), on: true)) == [0x90, 0x03, 0x40])
    #expect(SurfaceEncoder.encode(.led(.mute(0), on: false)) == [0x90, 0x03, 0x00])
}

@Test func everyNamedButtonIsUnique() {
    #expect(Set(Button.names.values).count == Button.names.count)
    // 24 strip buttons plus the 51 in columns 0A-0E (round3-left-top, round4-right).
    #expect(Button.names.count == 24 + 51)
}
