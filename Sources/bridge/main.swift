import BridgeRuntime
import Foundation

// Command line bridge: Digi 002 control port <-> virtual "003 MCU" port for Logic.
// Logs every translated message so behaviour can be checked against docs/protocol.md.
// Usage: bridge [--quiet]      (--quiet logs only state changes and errors)

setvbuf(stdout, nil, _IOLBF, 0)
let service = BridgeService(verbose: !CommandLine.arguments.contains("--quiet"))
service.onLog = { print($0) }

do {
    try service.start()
} catch {
    FileHandle.standardError.write(Data("bridge: \(error)\n".utf8))
    exit(1)
}

print("""
    bridge running: virtual port "\(BridgeService.virtualPortName)" is up.
    In Logic: Control Surfaces > Setup > New > Install > Mackie Designs Mackie Control,
    then set its Output Port and Input Port to "\(BridgeService.virtualPortName)". The desk wakes when
    Logic is running and sleeps when it is not. Ctrl-C to stop.
    """)
signal(SIGINT) { _ in exit(0) }
dispatchMain()
