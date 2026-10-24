/// Sends fader positions back to the desk so the motors hold each fader where it was
/// left, instead of returning it to the last host-set position on release.
///
/// Provisional, for capture sessions only. It relies on what docs/protocol.md has so far:
/// fader N reports `B0 (N-1) coarse` and `B0 (N-1+20) fine`, accepts `B0 cc coarse cc+20 fine`
/// (running status), and reports touch as `90 05 (40 + N-1)` and release as `90 05 (N-1)`.
/// A fader is echoed only when it is released, so the motor never fights a hand on it.
struct FaderEcho {
    private var coarse = [UInt8](repeating: 0, count: 8)
    private var fine = [UInt8](repeating: 0, count: 8)
    private var moved = Set<Int>()

    /// Takes one incoming packet and returns the messages to send back, if any.
    mutating func handle(_ bytes: [UInt8]) -> [[UInt8]] {
        var replies: [[UInt8]] = []
        var index = 0
        while index + 2 < bytes.count {
            let status = bytes[index], data1 = bytes[index + 1], data2 = bytes[index + 2]
            index += 3
            switch (status, data1) {
            case (0xB0, 0x00...0x07):
                coarse[Int(data1)] = data2
                moved.insert(Int(data1))
            case (0xB0, 0x20...0x27):
                fine[Int(data1 - 0x20)] = data2
                moved.insert(Int(data1 - 0x20))
            case (0x90, 0x05) where data2 & 0x40 == 0 && data2 < 8:
                let fader = Int(data2)
                if moved.remove(fader) != nil {
                    replies.append([0xB0, UInt8(fader), coarse[fader], UInt8(fader + 0x20), fine[fader]])
                }
            default:
                break
            }
        }
        return replies
    }
}
