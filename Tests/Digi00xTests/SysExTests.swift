import Testing
@testable import Digi00x

// Ring and display formats come from the Pro Tools 10.3.10 Digi002 bundle and were
// confirmed on the desk (sysex-ring-display.log, ring-red-displays.log).

@Test func ringLEDsAreTwoSevenBitMasks() {
    var ring = Ring()
    ring.light(1)
    #expect(SurfaceEncoder.encode(.ring(channel: 3, ring)) == [0xF0, 0x13, 0x00, 0x00, 0x03, 0x00, 0x01, 0xF7])
    ring = Ring()
    ring.light(1...7)
    #expect(SurfaceEncoder.encode(.ring(channel: 0, ring)) == [0xF0, 0x13, 0x00, 0x00, 0x00, 0x00, 0x7F, 0xF7])
    ring = Ring()
    ring.light(8...14)
    #expect(SurfaceEncoder.encode(.ring(channel: 1, ring)) == [0xF0, 0x13, 0x00, 0x00, 0x01, 0x7F, 0x00, 0xF7])
    ring = Ring()
    ring.light(8)
    #expect(SurfaceEncoder.encode(.ring(channel: 7, ring)) == [0xF0, 0x13, 0x00, 0x00, 0x07, 0x01, 0x00, 0xF7])
}

@Test func lastRingLEDIsGreenOrRedInTheStripByte() {
    #expect(SurfaceEncoder.encode(.ring(channel: 0, Ring(lastGreen: true))) == [0xF0, 0x13, 0x00, 0x00, 0x20, 0x00, 0x00, 0xF7])
    var ring = Ring(lastRed: true)
    ring.light(1...3)
    #expect(SurfaceEncoder.encode(.ring(channel: 0, ring)) == [0xF0, 0x13, 0x00, 0x00, 0x40, 0x00, 0x07, 0xF7])
    #expect(SurfaceEncoder.encode(.ring(channel: 2, .off)) == [0xF0, 0x13, 0x00, 0x00, 0x02, 0x00, 0x00, 0xF7])
}

@Test func ringIgnoresLEDsOutsideTheArc() {
    var ring = Ring()
    ring.light(0)
    ring.light(15)
    #expect(ring == .off)
}

@Test func displayIsFourCharactersWithAMode() {
    #expect(SurfaceEncoder.encode(.display(strip: 0, text: "abcd", inverse: false)) ==
            [0xF0, 0x13, 0x00, 0x40, 0x00, 0x78, 0x00, 0x61, 0x62, 0x63, 0x64, 0xF7])
    #expect(SurfaceEncoder.encode(.display(strip: 1, text: "TEST", inverse: true)) ==
            [0xF0, 0x13, 0x00, 0x40, 0x01, 0x7C, 0x00, 0x54, 0x45, 0x53, 0x54, 0xF7])
    // Short text is padded; long text is cut.
    #expect(SurfaceEncoder.encode(.display(strip: 8, text: "AB", inverse: false)) ==
            [0xF0, 0x13, 0x00, 0x40, 0x08, 0x78, 0x00, 0x41, 0x42, 0x20, 0x20, 0xF7])
    #expect(SurfaceEncoder.encode(.display(strip: 9, text: "TIMECODE", inverse: false)) ==
            [0xF0, 0x13, 0x00, 0x40, 0x09, 0x78, 0x00, 0x54, 0x49, 0x4D, 0x45, 0xF7])
}

@Test func displayPacksTheTopBitOfEachCharacter() {
    // Bit 7 of character 0 goes in the mode byte; of 1, 2, 3 in bits 4, 2, 0 of the next byte.
    #expect(SurfaceEncoder.encode(.display(strip: 0, text: "\u{C1}BCD", inverse: false)) ==
            [0xF0, 0x13, 0x00, 0x40, 0x00, 0x79, 0x00, 0x41, 0x42, 0x43, 0x44, 0xF7])
    #expect(SurfaceEncoder.encode(.display(strip: 0, text: "A\u{C2}\u{C3}\u{C4}", inverse: false)) ==
            [0xF0, 0x13, 0x00, 0x40, 0x00, 0x78, 0x15, 0x41, 0x42, 0x43, 0x44, 0xF7])
    // Characters outside Latin-1 become '?'.
    #expect(SurfaceEncoder.encode(.display(strip: 0, text: "→", inverse: false))[7] == 0x3F)
}
