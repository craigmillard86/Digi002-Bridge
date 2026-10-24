import Foundation
import MIDIIO

/// Writes timestamped lines to stdout and to a log file. Safe to call from any thread.
///
/// Line format, one event per line:
///
///     <ms since start>  <kind>  <payload>
///
/// kind is IN (from the surface), OUT (sent by us) or LABEL (typed by the user and
/// applying to the IN lines that follow it). Lines starting with # are comments.
final class CaptureLog {
    private let file: FileHandle
    private let startHostTime: UInt64
    private let lock = NSLock()

    init(path: String, header: [String]) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
        }
        file = try FileHandle(forWritingTo: url)
        startHostTime = HostTime.now()
        for line in header { write("# " + line) }
    }

    func event(_ kind: String, _ payload: String, hostTime: UInt64 = 0) {
        let time = hostTime == 0 ? HostTime.now() : hostTime
        let elapsed = time > startHostTime ? HostTime.nanoseconds(time - startHostTime) : 0
        let ms = String(format: "%10.3f", Double(elapsed) / 1_000_000)
        write("\(ms)  \(kind.padding(toLength: 5, withPad: " ", startingAt: 0))  \(payload)")
    }

    func comment(_ text: String) {
        write("# " + text)
    }

    private func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        print(line)
        file.write(Data((line + "\n").utf8))
    }
}
