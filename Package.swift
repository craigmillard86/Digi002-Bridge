// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "logic-bridge",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "capture", targets: ["capture"]),
        .executable(name: "bridge", targets: ["bridge"]),
        .executable(name: "BridgeApp", targets: ["BridgeApp"]),
    ],
    targets: [
        // CoreMIDI access only. Knows nothing about the 00x surface or Mackie Control.
        .target(name: "MIDIIO"),
        // The Digi 002 surface protocol (docs/protocol.md). Pure codec, no I/O.
        .target(name: "Digi00x"),
        // The Mackie Control subset spoken to Logic. Pure codec, no I/O.
        .target(name: "MCU"),
        // Translation between the two protocols. No I/O.
        .target(name: "BridgeCore", dependencies: ["Digi00x", "MCU"]),
        // Runs the bridge: MIDI client, virtual port, desk connection, timer, Logic detection.
        // Shared by the command line tool and the app.
        .target(name: "BridgeRuntime", dependencies: ["MIDIIO", "Digi00x", "MCU", "BridgeCore"]),
        // Phase 1 tool: list ports, log Port 3 (Control) traffic, send probe bytes.
        .executableTarget(name: "capture", dependencies: ["MIDIIO"]),
        // Phase 3: the bridge as a command line tool.
        .executableTarget(name: "bridge", dependencies: ["BridgeRuntime"]),
        // Phase 4: the setup app ("002 Bridge.app", built by tools/make-app.sh).
        .executableTarget(name: "BridgeApp", dependencies: ["BridgeRuntime"]),
        .testTarget(name: "MIDIIOTests", dependencies: ["MIDIIO"]),
        .testTarget(name: "Digi00xTests", dependencies: ["Digi00x"]),
        .testTarget(name: "MCUTests", dependencies: ["MCU"]),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore", "Digi00x", "MCU"]),
    ]
)
