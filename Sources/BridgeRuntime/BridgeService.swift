import AppKit
import BridgeCore
import Digi00x
import Foundation
import MCU
import MIDIIO

/// Runs the bridge: owns the MIDI client, the virtual "003 MCU" port that Logic talks
/// to, the connection to the desk and the timer. The command line tool and the app both
/// wrap this. All callbacks arrive on the service's own queue; the app hops to main.
///
/// The desk is only connected while Logic Pro runs. With no client on its control port
/// it drops to standby (faders parked, "Digi 002 / Standby"), which is the right state
/// when Logic is closed; when Logic starts, the bridge connects and Logic sends its state.
public final class BridgeService {
    public enum DeskState: Equatable {
        case notFound    // no Avid device with a control port on this Mac
        case standby     // found, not connected (Logic is not running)
        case waking      // connected, waiting for the desk to accept commands
        case connected
    }

    public struct Status: Equatable {
        public var running = false
        public var desk = DeskState.notFound
        /// The desk's port name as CoreMIDI shows it, e.g. "Avid 002 Port 3 (Control)".
        public var deskName = ""
        public var logicRunning = false
        /// Logic has sent Mackie Control data in the last few seconds, so it is set up.
        public var logicTalking = false
        public var lastError: String?
    }

    public static let virtualPortName = "003 MCU"
    /// Fixed so Logic recognises the port across restarts (see VirtualPort). Arbitrary value.
    public static let virtualPortUniqueID: Int32 = 0x0030_3343
    public static let logicBundleID = "com.apple.logic10"
    /// The desk ignores messages for a few seconds after a client connects
    /// (docs/protocol.md, Connection behaviour). Until then, commands are not sent; the
    /// bridge replays the current state once it is awake.
    public static let deskWakeSeconds = 5.0
    /// How long a display shows a changed value before going back to the track name.
    public static let displayValueSeconds = 1.5
    /// The desk and Logic are looked for this often, in ticks of `Bridge.tickSeconds`.
    static let checkTicks = 10
    static let logicSilentSeconds = 5.0

    public private(set) var status = Status() {
        didSet { if status != oldValue { onStatus?(status) } }
    }
    public var onStatus: ((Status) -> Void)?
    public var onLog: ((String) -> Void)?
    /// Whether every translated message is logged, or only state changes and errors.
    public var verbose: Bool

    // All translation happens on this queue, so the bridge state needs no lock.
    private let queue = DispatchQueue(label: "bridge")
    private var connection: MIDIConnection?
    private var logicPort: VirtualPort?
    private var deskSource: Endpoint?
    private var deskDestination: Endpoint?
    private var deskConnected = false
    private var deskAwake = false
    private var wakeGeneration = 0
    private var bridge = Bridge()
    private var surfaceDecoder = SurfaceDecoder()
    private var mcuDecoder = MCUDecoder()
    private var ticker: DispatchSourceTimer?
    private var ticks = 0
    private var lastFromLogic = Date.distantPast
    private var lastMeterLog = Date.distantPast
    private let startTime = Date()

    public init(verbose: Bool = true) {
        self.verbose = verbose
    }

    /// Creates the MIDI client and the "003 MCU" port and starts looking for the desk and
    /// for Logic. Throws only if CoreMIDI refuses; a missing desk is a status, not an error.
    public func start() throws {
        try queue.sync {
            guard connection == nil else { return }
            let connection = try MIDIConnection(name: "003 bridge")
            logicPort = try VirtualPort(name: Self.virtualPortName, uniqueID: Self.virtualPortUniqueID,
                                        on: connection) { [weak self] _, bytes in
                self?.queue.async { self?.receiveFromLogic(bytes) }
            }
            self.connection = connection
            status.running = true
            status.lastError = nil
            log("bridge started; virtual port \"\(Self.virtualPortName)\" is up")

            let ticker = DispatchSource.makeTimerSource(queue: queue)
            ticker.schedule(deadline: .now() + Bridge.tickSeconds, repeating: Bridge.tickSeconds)
            ticker.setEventHandler { [weak self] in self?.tick() }
            ticker.resume()
            self.ticker = ticker
            check()
        }
    }

    /// Disconnects the desk (it goes to standby) and takes the virtual port down.
    public func stop() {
        queue.sync {
            ticker?.cancel()
            ticker = nil
            disconnectDesk()
            logicPort = nil
            connection = nil
            deskSource = nil
            deskDestination = nil
            status = Status()
            log("bridge stopped")
        }
    }

    public func restart() throws {
        stop()
        try start()
    }

    // MARK: Desk and Logic

    private func tick() {
        ticks += 1
        let commands = bridge.tick()
        if deskAwake { sendToDesk(commands) }
        if ticks % Self.checkTicks == 0 { check() }
    }

    private func check() {
        if deskSource == nil || deskDestination == nil {
            deskSource = Endpoints.controlPort(.source)
            deskDestination = Endpoints.controlPort(.destination)
            if let deskSource, deskDestination != nil {
                status.deskName = deskSource.displayName
                status.desk = .standby
                log("desk found: \(deskSource.displayName)")
            } else {
                status.desk = .notFound
            }
        }
        let logicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.logicBundleID).isEmpty
        if logicRunning != status.logicRunning {
            status.logicRunning = logicRunning
            log(logicRunning ? "Logic Pro is running" : "Logic Pro is not running; the desk stays in standby until it starts")
        }
        if logicRunning, !deskConnected, deskSource != nil { connectDesk() }
        if !logicRunning, deskConnected { disconnectDesk() }
        status.logicTalking = logicRunning && Date().timeIntervalSince(lastFromLogic) < Self.logicSilentSeconds
    }

    private func connectDesk() {
        guard let deskSource, !deskConnected, let connection else { return }
        do {
            try connection.listen(to: deskSource) { [weak self] _, bytes in
                self?.queue.async { self?.receiveFromDesk(bytes) }
            }
        } catch {
            report("could not connect to the desk: \(error)")
            return
        }
        deskConnected = true
        deskAwake = false
        status.desk = .waking
        wakeGeneration += 1
        let generation = wakeGeneration
        log("desk connected, waiting \(Self.deskWakeSeconds) s for it to wake")
        queue.asyncAfter(deadline: .now() + Self.deskWakeSeconds) { [weak self] in
            guard let self, self.deskConnected, generation == self.wakeGeneration else { return }
            self.deskAwake = true
            self.status.desk = .connected
            let commands = self.bridge.startup()
            self.log("desk awake, sending \(commands.count) state commands")
            self.sendToDesk(commands)
        }
    }

    private func disconnectDesk() {
        guard deskConnected else { return }
        if let deskSource, let connection {
            do { try connection.stopListening(to: deskSource) } catch { report("disconnect failed: \(error)") }
        }
        deskConnected = false
        deskAwake = false
        bridge = Bridge()                // Logic's state went with it
        surfaceDecoder = SurfaceDecoder()
        if status.desk != .notFound { status.desk = .standby }
        log("desk disconnected; it goes back to standby")
    }

    // MARK: Traffic

    private func receiveFromDesk(_ bytes: [UInt8]) {
        for event in surfaceDecoder.decode(bytes) {
            let out = bridge.fromSurface(event)
            trace("desk -> \(event) => Logic \(out.toLogic)")
            deliver(out)
        }
    }

    private func receiveFromLogic(_ bytes: [UInt8]) {
        lastFromLogic = Date()
        let messages = mcuDecoder.decode(bytes)
        if messages.isEmpty {
            trace("Logic -> (unhandled) \(Hex.format(bytes))")
        }
        for message in messages {
            let out = bridge.fromLogic(message)
            var frequent = false     // meters and timecode arrive many times a second
            switch message {
            case .meter:
                frequent = true
                // One meter message every few seconds, so it is clear Logic sends them.
                let now = Date()
                if now.timeIntervalSince(lastMeterLog) > 5 {
                    lastMeterLog = now
                    trace("Logic -> \(message) (meters: one logged per 5 s)")
                }
            case .sevenSegment: frequent = true
            default: break
            }
            if !out.toSurface.isEmpty && !frequent {
                if case let .lcd(offset, text) = message {
                    let line = String(text.map { Character(UnicodeScalar($0)) })
                    trace("Logic -> lcd \(offset) \"\(line)\" => desk \(out.toSurface)")
                } else {
                    trace("Logic -> \(message) => desk \(out.toSurface)")
                }
            }
            deliver(out)
        }
    }

    private func deliver(_ out: Bridge.Output) {
        for message in out.toLogic {
            let bytes = MCUEncoder.encode(message)
            do { try logicPort?.send(bytes) } catch { report("to Logic failed: \(error)") }
        }
        for revert in out.displayReverts {
            queue.asyncAfter(deadline: .now() + Self.displayValueSeconds) { [weak self] in
                guard let self else { return }
                let commands = self.bridge.revertDisplay(revert)
                if self.deskAwake { self.sendToDesk(commands) }
            }
        }
        guard deskAwake else { return }
        sendToDesk(out.toSurface)
    }

    private func sendToDesk(_ commands: [SurfaceCommand]) {
        guard deskConnected, let connection, let deskDestination else { return }
        for command in commands {
            let bytes = SurfaceEncoder.encode(command)
            do { try connection.send(bytes, to: deskDestination) } catch { report("to desk failed: \(error)") }
        }
    }

    // MARK: Logging

    /// State changes and errors: always logged.
    private func log(_ text: String) {
        onLog?(String(format: "%9.3f  ", Date().timeIntervalSince(startTime)) + text)
    }

    /// Per-message traffic: only when verbose.
    private func trace(_ text: String) {
        if verbose { log(text) }
    }

    private func report(_ text: String) {
        status.lastError = text
        log(text)
    }
}
