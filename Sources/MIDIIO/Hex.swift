/// Hex text to and from bytes, for logs and for typing probe messages.
public enum Hex {
    public struct ParseError: Error, CustomStringConvertible {
        public let token: String
        public var description: String { "not a hex byte sequence: \"\(token)\"" }
    }

    /// Formats bytes as upper-case pairs separated by spaces: "90 00 7F".
    public static func format(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }.joined(separator: " ")
    }

    /// Parses "90 00 7f", "90007F", "0x90,0x00,0x7f" and mixes of these.
    /// A token of one digit is one byte; longer tokens must have an even number of digits.
    public static func parse(_ text: String) throws -> [UInt8] {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        var bytes: [UInt8] = []
        for raw in tokens {
            var token = Substring(raw)
            if token.hasPrefix("0x") || token.hasPrefix("0X") { token = token.dropFirst(2) }
            guard !token.isEmpty, token.allSatisfy(\.isHexDigit) else {
                throw ParseError(token: String(raw))
            }
            if token.count == 1 {
                bytes.append(UInt8(token, radix: 16)!)
                continue
            }
            guard token.count % 2 == 0 else { throw ParseError(token: String(raw)) }
            var index = token.startIndex
            while index < token.endIndex {
                let next = token.index(index, offsetBy: 2)
                bytes.append(UInt8(token[index..<next], radix: 16)!)
                index = next
            }
        }
        return bytes
    }
}
