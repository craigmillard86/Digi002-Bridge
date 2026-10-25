import BridgeRuntime
import Foundation

// Command line bridge: Digi 002 control port <-> virtual "003 MCU" port for Logic.
// Logs every translated message so behaviour can be checked against docs/protocol.md.
// Usage: bridge [--quiet] [--config path]
//   --quiet   logs only state changes and errors
//   --config  settings file to use instead of ~/Library/Application Support/002 Bridge/config.json

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
var configURL = ConfigFile.url
if let i = arguments.firstIndex(of: "--config"), i + 1 < arguments.count {
    configURL = URL(fileURLWithPath: arguments[i + 1])
}
let outcome = ConfigFile.load(from: configURL)
let service = BridgeService(verbose: !arguments.contains("--quiet"), config: ConfigFile.config(from: outcome))
service.onLog = { print($0) }
switch outcome {
case .defaults: print("settings: defaults (no file at \(configURL.path))")
case .loaded: print("settings: \(configURL.path)")
case let .invalid(reason): print("settings: could not read \(reason); using defaults")
}

do {
    try service.start()
} catch {
    FileHandle.standardError.write(Data("bridge: \(error.localizedDescription)\n".utf8))
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
