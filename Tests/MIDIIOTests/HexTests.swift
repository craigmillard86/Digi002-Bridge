import Testing
@testable import MIDIIO

@Test func formatsUpperCasePairs() {
    #expect(Hex.format([0x90, 0x00, 0x7F]) == "90 00 7F")
    #expect(Hex.format([]) == "")
}

@Test func parsesSpacedPairs() throws {
    #expect(try Hex.parse("90 00 7f") == [0x90, 0x00, 0x7F])
}

@Test func parsesRunTogetherDigits() throws {
    #expect(try Hex.parse("F0000137F7") == [0xF0, 0x00, 0x01, 0x37, 0xF7])
}

@Test func parsesPrefixedAndCommaSeparated() throws {
    #expect(try Hex.parse("0x90,0x00, 0x7F") == [0x90, 0x00, 0x7F])
}

@Test func parsesSingleDigitAsOneByte() throws {
    #expect(try Hex.parse("b0 7 7f") == [0xB0, 0x07, 0x7F])
}

@Test func rejectsOddLengthAndNonHex() {
    #expect(throws: Hex.ParseError.self) { try Hex.parse("900") }
    #expect(throws: Hex.ParseError.self) { try Hex.parse("90 zz") }
    #expect(throws: Hex.ParseError.self) { try Hex.parse("0x") }
}

@Test func formatAndParseRoundTrip() throws {
    let bytes = (0...255).map { UInt8($0) }
    #expect(try Hex.parse(Hex.format(bytes)) == bytes)
}
