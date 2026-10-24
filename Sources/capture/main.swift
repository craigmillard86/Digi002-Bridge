import Foundation
import MIDIIO

let usage = """
    capture: talk to the Digi 00x control surface port ("Port 3 (Control)").

    Usage:
      capture list
          List every MIDI source and destination and say whether the control port was found.

      capture log [--port NAME] [--out FILE] [--echo]
          Log every packet from the control port to the terminal and to FILE
          (default: captures/<date>-<time>.log). While it runs, type a line and press
          return to add a label, e.g. "fader1 up", which tags the bytes that follow.
          Type "> 90 00 7F" to send bytes to the control port; they are logged as OUT.
          Type "quit" or press ctrl-D to stop.
          --echo sends each fader's final position back when you let go of it, so the
          motors hold it there; these are logged as ECHO.

      capture send [--port NAME] [--hold SECONDS] HEX...
          Send one message to the control port and exit, e.g. capture send F0 00 01 F7.
          The desk wakes from standby only while a client is connected and takes a few
          seconds to do so, so by default send waits 5 s, sends, then stays connected
          for --hold seconds (default 10) so you can see the result.

    Fader positions must be sent with running status, e.g. "B0 00 7F 20 70".

    --port NAME uses the first source/destination whose name contains NAME instead of
    looking for "Port 3 (Control)" on the Avid device.
    """

setvbuf(stdout, nil, _IOLBF, 0)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("capture: " + message + "\n").utf8))
    exit(1)
}

/// Pulls "--name value" out of the argument list and returns the value.
func option(_ name: String, from args: inout [String]) -> String? {
    guard let index = args.firstIndex(of: name) else { return nil }
    guard index + 1 < args.count else { fail("\(name) needs a value") }
    let value = args[index + 1]
    args.removeSubrange(index...(index + 1))
    return value
}

func findPort(_ direction: Endpoint.Direction, override: String?) -> Endpoint {
    let found = override.map { Endpoints.matching($0, direction) } ?? Endpoints.controlPort(direction)
    guard let found else {
        let wanted = override.map { "a \(direction) matching \"\($0)\"" }
            ?? "the \(Endpoints.controlPortName) \(direction) on an Avid device"
        fail("could not find \(wanted). Run 'capture list' to see what is there.")
    }
    return found
}

func runList() {
    for (title, endpoints) in [("Sources", Endpoints.sources()), ("Destinations", Endpoints.destinations())] {
        print("\(title):")
        if endpoints.isEmpty { print("  (none)") }
        for ep in endpoints {
            var line = "  \(ep.displayName)"
            if !ep.deviceName.isEmpty { line += "   [device \"\(ep.deviceName)\", port \"\(ep.entityName)\"]" }
            if ep.isOffline { line += "   OFFLINE" }
            print(line)
        }
    }
    let source = Endpoints.controlPort(.source)
    let destination = Endpoints.controlPort(.destination)
    print("")
    print("Control port source:      " + (source.map { $0.displayName } ?? "NOT FOUND"))
    print("Control port destination: " + (destination.map { $0.displayName } ?? "NOT FOUND"))
    if source == nil || destination == nil { exit(1) }
}

/// Seconds the desk needs after a client connects before it acts on messages.
let standbyWakeSeconds = 5.0

func runSend(_ args: [String], portOverride: String?, hold: Double) {
    guard !args.isEmpty else { fail("send needs some hex bytes") }
    let bytes: [UInt8]
    do { bytes = try Hex.parse(args.joined(separator: " ")) } catch { fail("\(error)") }
    let source = findPort(.source, override: portOverride)
    let destination = findPort(.destination, override: portOverride)
    do {
        // Connect to the source as well, as log does. Which of the two wakes the desk
        // is not yet known.
        let connection = try MIDIConnection(name: "capture")
        try connection.listen(to: source) { _, _ in }
        print("waiting \(Int(standbyWakeSeconds)) s for the desk to leave standby")
        Thread.sleep(forTimeInterval: standbyWakeSeconds)
        try connection.send(bytes, to: destination)
        print("sent \(Hex.format(bytes)) to \(destination.displayName), holding \(hold) s")
        // Disconnecting puts the desk back in standby, which undoes LEDs and motors.
        Thread.sleep(forTimeInterval: max(hold, 0.2))
    } catch {
        fail("\(error)")
    }
}

func runLog(outPath: String?, portOverride: String?, echo: Bool) {
    let source = findPort(.source, override: portOverride)
    let destination = findPort(.destination, override: portOverride)

    let stamp = DateFormatter()
    stamp.locale = Locale(identifier: "en_US_POSIX")
    stamp.dateFormat = "yyyyMMdd-HHmmss"
    let path = outPath ?? "captures/\(stamp.string(from: Date())).log"

    let log: CaptureLog
    let connection: MIDIConnection
    do {
        log = try CaptureLog(path: path, header: [
            "capture log started \(ISO8601DateFormatter().string(from: Date()))",
            "source:      \(source.displayName)",
            "destination: \(destination.displayName)",
            "columns: ms since start, IN/OUT/ECHO/LABEL, bytes in hex or label text",
            "fader echo: \(echo ? "on" : "off")",
        ])
        connection = try MIDIConnection(name: "capture")
        // Only touched from the CoreMIDI receive thread, so it needs no lock.
        var faderEcho = FaderEcho()
        try connection.listen(to: source) { [unowned connection] hostTime, bytes in
            log.event("IN", Hex.format(bytes), hostTime: hostTime)
            guard echo else { return }
            for reply in faderEcho.handle(bytes) {
                do {
                    try connection.send(reply, to: destination)
                    log.event("ECHO", Hex.format(reply))
                } catch {
                    log.comment("echo not sent: \(error)")
                }
            }
        }
    } catch {
        fail("\(error)")
    }
    FileHandle.standardError.write(Data("logging to \(path). Type a label, \"> hex\" to send, or quit.\n".utf8))

    // Ctrl-C ends the log cleanly instead of leaving it without a footer.
    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    interrupt.setEventHandler {
        log.comment("stopped (ctrl-C)")
        exit(0)
    }
    interrupt.resume()

    while let line = readLine() {
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { continue }
        if text == "quit" || text == "exit" { break }
        if text.hasPrefix(">") {
            do {
                let bytes = try Hex.parse(String(text.dropFirst()))
                guard !bytes.isEmpty else { continue }
                try connection.send(bytes, to: destination)
                log.event("OUT", Hex.format(bytes))
            } catch {
                FileHandle.standardError.write(Data("not sent: \(error)\n".utf8))
            }
            continue
        }
        log.event("LABEL", text)
    }
    log.comment("stopped")
}

var args = Array(CommandLine.arguments.dropFirst())
let portOverride = option("--port", from: &args)
let outPath = option("--out", from: &args)
let holdText = option("--hold", from: &args)
guard let hold = Double(holdText ?? "10") else { fail("--hold needs a number of seconds") }
let echo = args.contains("--echo")
args.removeAll { $0 == "--echo" }

switch args.first {
case "list": runList()
case "log": runLog(outPath: outPath, portOverride: portOverride, echo: echo)
case "send": runSend(Array(args.dropFirst()), portOverride: portOverride, hold: hold)
case nil, "help", "-h", "--help": print(usage)
default: fail("unknown command \"\(args[0])\"\n\n" + usage)
}
