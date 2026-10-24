import Testing
@testable import MCU

@Test func metersAreChannelPressure() {
    var decoder = MCUDecoder()
    // bridge-run-4.log: Logic sends D0 with the channel in the high nibble.
    #expect(decoder.decode([0xD0, 0x29]) == [.meter(channel: 2, level: 9)])
    #expect(decoder.decode([0xD0, 0x7E, 0x0F]) == [.meter(channel: 7, level: 14), .meter(channel: 0, level: 15)])
    #expect(decoder.decode(MCUEncoder.encode(.meter(channel: 5, level: 12))) == [.meter(channel: 5, level: 12)])
}

@Test func flashVelocityIsSeparateFromOn() {
    var decoder = MCUDecoder()
    #expect(decoder.decode([0x90, 0x00, 0x01]) == [.ledFlash(.recArm(0))])
    #expect(decoder.decode([0x90, 0x00, 0x7F]) == [.note(.recArm(0), on: true)])
    #expect(decoder.decode(MCUEncoder.encode(.ledFlash(.play))) == [.ledFlash(.play)])
}

@Test func sevenSegmentCharactersDecode() {
    var decoder = MCUDecoder()
    // bridge-run-4.log: B0 4x timecode digits.
    #expect(decoder.decode([0xB0, 0x49, 0x31]) == [.sevenSegment(position: 9, character: "1", dot: false)])
    #expect(decoder.decode([0xB0, 0x46, 0x60]) == [.sevenSegment(position: 6, character: " ", dot: true)])
    // 0x00-0x1F stand for 0x40-0x5F.
    #expect(decoder.decode([0xB0, 0x4A, 0x10]) == [.sevenSegment(position: 10, character: "P", dot: false)])
    for character in ["A", "Z", " ", "9", "-"] as [Character] {
        let message = MCUMessage.sevenSegment(position: 3, character: character, dot: false)
        #expect(decoder.decode(MCUEncoder.encode(message)) == [message])
    }
}
