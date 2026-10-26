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
        case settling    // found and wanted, but released or switched on too recently to take again
        case waking      // connected, waiting for the desk to accept commands
        case connected
        /// Connected, but the desk is not taking commands: the driver's buffer to it has
        /// filled and every message now takes a second to be dropped. Only switching the
        /// desk off and on clears it. Seen after the desk was taken again within a few
        /// seconds of being released, while it was still going to standby.
        case deaf
        /// Connected, but the desk has stopped following: its faders spring back after they
        /// are released, so it is not taking commands. Reconnecting clears it (the bridge
        /// does that by itself unless told not to, or until it stops working).
        case notFollowing
    }

    public struct Status: Equatable {
        public var running = false
        public var desk = DeskState.notFound {
            didSet { if desk != oldValue { deskChangedAt = Date() } }
        }
        /// When `desk` last changed, for "connected since" in the app.
        public var deskChangedAt: Date?
        /// The desk's port name as CoreMIDI shows it, e.g. "Avid 002 Port 3 (Control)".
        public var deskName = ""
        /// The host application's name ("Logic Pro" unless the config names another).
        public var hostName = "Logic Pro"
        public var logicRunning = false {
            didSet { if logicRunning != oldValue { logicChangedAt = Date() } }
        }
        public var logicChangedAt: Date?
        /// Logic has sent Mackie Control data in the last few seconds, so it is set up.
        public var logicTalking = false
        /// When Logic last sent anything, to the second.
        public var lastMessageAt: Date?
        /// Logic is running but did not answer the bridge's last announcement. A live Logic
        /// answers within a few milliseconds, so this means its MIDI ports are dead (see
        /// `midiServerRestartedAt`), no project is open, or the surface is not set up.
        public var logicDeaf = false
        /// When the MIDI server went away while Logic was open. Logic's ports went with
        /// it and it sends and hears nothing until it is quit and opened again.
        public var midiServerRestartedAt: Date?
        /// When the desk was last noticed to have stopped following (see `StuckDetector`),
        /// until it is connected again.
        public var stuckAt: Date?
        public var lastError: String?

        public init() {}
    }

    public enum StartError: LocalizedError {
        /// A "003 MCU" port already exists, so the app or the command line tool is running.
        /// Two copies both hold the desk (it never reaches standby and ignores commands)
        /// and Logic talks to only one of them, so a second copy must not start.
        case anotherBridgeRunning

        public var errorDescription: String? {
            switch self {
            case .anotherBridgeRunning:
                return "another copy of the bridge is already running (the 002 Bridge app or the command line tool); quit it first"
            }
        }
    }

    public static let virtualPortName = "003 MCU"
    /// Fixed so Logic recognises the port across restarts (see VirtualPort). Arbitrary value.
    public static let virtualPortUniqueID: Int32 = 0x0030_3343
    /// The desk ignores messages for a few seconds after a client connects
    /// (docs/protocol.md, Connection behaviour). Until then, commands are not sent; the
    /// bridge replays the current state once it is awake. The wait is `config.deskWakeSeconds`.
    /// Spacing between commands when the whole state is replayed to a just-woken desk,
    /// and the delay before the replay is repeated.
    static let replaySpacingSeconds = 0.008
    static let replayRepeatSeconds = 3.0
    /// The desk takes a few seconds to go to standby after a client releases it, and to
    /// settle after it is switched on. A client arriving in that window has left it deaf
    /// (see `DeskState.deaf`), so no connection is made until this long after either.
    static let settleSeconds = 10.0
    /// A send that takes longer than this is waiting on the driver's full buffer.
    static let slowSendSeconds = 0.5
    /// The desk and Logic are looked for this often, in ticks of `Bridge.tickSeconds`.
    static let checkTicks = 10
    static let logicSilentSeconds = 5.0
    /// Logic answers an announcement in well under a second; nothing in this long means
    /// it never got it.
    static let probeAnswerSeconds = 3.0
    /// How often a silent Logic is announced to again while the desk is sending it events.
    static let probeRepeatSeconds = 60.0
    /// Desk events going to a Logic that has been quiet this long prompt a probe.
    static let probeSilentSeconds = 20.0
    /// Device queries within this long of the last announcement are not answered again:
    /// Logic asks several times in a burst, and each answer makes it re-send its state.
    static let announceGapSeconds = 1.0
    /// Fader snap-backs (see `StuckDetector`) within the window before the desk counts as
    /// stuck; one on its own can be a fluke.
    static let stuckStrikesNeeded = 2
    static let stuckStrikeWindowSeconds = 60.0
    /// Reconnects of a stuck desk within the window before the bridge stops trying.
    static let stuckReconnectsBeforeGivingUp = 2
    static let stuckReconnectWindowSeconds = 300.0
    /// The serial this surface reports in the Mackie Control handshake ("002BRG", 7 bytes).
    static let serial: [UInt8] = Array("002BRGE".utf8)
    static let challenge: [UInt8] = [0x01, 0x02, 0x03, 0x04]
    /// Reported to Logic's version request: five characters, as a Mackie Control sends.
    static let version = "V1.00"

    public private(set) var status = Status() {
        didSet { if status != oldValue { onStatus?(status) } }
    }
    public var onStatus: ((Status) -> Void)?
    public var onLog: ((String) -> Void)?
    /// Every command the bridge produces for the desk, whether or not a desk is there to
    /// take it, so a picture of the desk can be kept. Called on the service's queue.
    public var onSurface: (([SurfaceCommand]) -> Void)?
    /// The settings in force. Change them with `apply`.
    public private(set) var config: BridgeConfig
    /// Whether every translated message is logged, or only state changes and errors.
    public var verbose: Bool

    // All translation happens on this queue, so the bridge state needs no lock.
    private let queue = DispatchQueue(label: "bridge")
    /// Hosts the virtual port Logic talks to. Lives as long as the service runs.
    private var logicConnection: MIDIConnection?
    /// The desk's client. Avid's driver treats a CoreMIDI client as "connected" for as long
    /// as it exists, whatever its ports do, so this one is created when Logic starts and
    /// destroyed when Logic quits; only then does the desk go to standby.
    private var deskConnection: MIDIConnection?
    /// The desk's audio engine, run silently while connected (see `DeskAudio`).
    private let deskAudio = DeskAudio()
    static let audioReleaseSeconds = 1.0
    private var logicPort: VirtualPort?
    private var deskSource: Endpoint?
    private var deskDestination: Endpoint?
    private var deskConnected = false
    private var deskAwake = false
    private var deskDeaf = false
    /// When the desk was last released or appeared, for `settleSeconds`.
    private var deskReleasedAt = Date.distantPast
    private var settleAnnounced = false
    private var restarting = false
    private var wakeGeneration = 0
    private var bridge: Bridge
    private var surfaceDecoder = SurfaceDecoder()
    private var mcuDecoder = MCUDecoder()
    private var ticker: DispatchSourceTimer?
    private var ticks = 0
    private var lastFromLogic = Date.distantPast
    /// When the last announcement went to Logic and is still unanswered.
    private var probeSentAt: Date?
    private var lastProbeAt = Date.distantPast
    /// Set when the MIDI server went away with Logic open; kept across the restart.
    private var logicPortsLostAt: Date?
    private var lastMeterLog = Date.distantPast
    private var stuckDetector = StuckDetector()
    private var stuckStrikes: [Date] = []
    private var stuckReconnects: [Date] = []
    private let startTime = Date()

    public init(verbose: Bool = true, config: BridgeConfig = .default) {
        self.verbose = verbose
        self.config = config
        bridge = Bridge(config: config)
        status.hostName = Self.hostName(for: config.hostBundleID)
    }

    /// Puts new settings into effect without restarting: the desk is wiped and refilled
    /// so a changed button or display option shows at once.
    public func apply(_ config: BridgeConfig) {
        queue.async { [self] in
            guard config != self.config else { return }
            let hostChanged = config.hostBundleID != self.config.hostBundleID
            self.config = config
            status.hostName = Self.hostName(for: config.hostBundleID)
            bridge = Bridge(config: config)
            log("settings applied")
            if deskConnected {
                if config.holdAudioEngine { holdAudio() } else { releaseAudio() }
            }
            if hostChanged {
                if deskConnected { disconnectDesk() }
                check()
            } else if deskAwake {
                wakeGeneration += 1
                replayState(generation: wakeGeneration)
                announceToLogic()
            } else {
                onSurface?(bridge.startup())
            }
        }
    }

    /// Drops the desk connection and makes it again, for when the desk looks stuck.
    public func reconnectDesk() {
        queue.async { [self] in
            stuckStrikes = []
            stuckReconnects = []
            status.stuckAt = nil
            if deskConnected { disconnectDesk() }
            log("reconnecting the desk once it has settled")
            check()
        }
    }

    static func hostName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID == "com.apple.logic10" ? "Logic Pro" : bundleID
    }

    /// Creates the MIDI client and the "003 MCU" port and starts looking for the desk and
    /// for Logic. Throws only if CoreMIDI refuses; a missing desk is a status, not an error.
    public func start() throws {
        try queue.sync {
            guard logicConnection == nil else { return }
            if Self.anotherBridgeIsRunning() {
                let error = StartError.anotherBridgeRunning
                status.lastError = error.errorDescription
                log("not started: \(error.errorDescription ?? "")")
                throw error
            }
            deskAudio.onEvent = { [weak self] text in
                self?.queue.async { self?.log("desk audio: \(text)") }
            }
            // A port appearing or going (the desk switched on or off) is acted on at once
            // rather than at the next poll.
            let connection = try MIDIConnection(name: "003 bridge") { [weak self] in
                self?.queue.async { self?.check() }
            }
            logicPort = try VirtualPort(name: Self.virtualPortName, uniqueID: Self.virtualPortUniqueID,
                                        on: connection) { [weak self] _, bytes in
                self?.queue.async { self?.receiveFromLogic(bytes) }
            }
            logicConnection = connection
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
            logicConnection = nil
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

    /// Whether some other process already publishes the "003 MCU" port. A virtual port has
    /// no device behind it, which tells it apart from a hardware port of the same name.
    static func anotherBridgeIsRunning() -> Bool {
        Endpoints.sources().contains { $0.displayName == virtualPortName && $0.deviceName.isEmpty }
    }

    // MARK: Desk and Logic

    private func tick() {
        ticks += 1
        emit(bridge.tick())
        for snapBack in stuckDetector.confirmed(at: Date()) { noteSnapBack(snapBack) }
        if ticks % Self.checkTicks == 0 { check() }
    }

    private func check() {
        guard !restarting else { return }
        // The MIDI server can crash (Avid's driver takes it down when the desk is switched
        // off with its buffer full). Every port then goes, this process's client with them,
        // and the only way back is a fresh client: the bridge restarts itself.
        let sources = Endpoints.sources()
        if logicPort != nil, !sources.contains(where: { $0.displayName == Self.virtualPortName && $0.deviceName.isEmpty }) {
            restarting = true
            log("the MIDI server has gone away (\(sources.isEmpty ? "no ports at all" : "the bridge's own port is missing")); restarting the bridge")
            if status.logicRunning {
                logicPortsLostAt = Date()
                log("\(status.hostName) was open, so its MIDI ports went with the server: it must be quit and opened again")
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                do { try self.restart() } catch { self.report("restart after the MIDI server went away failed: \(error)") }
                self.queue.async { self.restarting = false }
            }
            return
        }
        // The desk's ports come and go with its power switch (Avid's driver removes them
        // when the desk is off and creates new ones when it is back), so they are looked
        // up every time rather than once.
        let source = Endpoints.controlPort(.source)
        let destination = Endpoints.controlPort(.destination)
        if let known = deskSource, source?.ref != known.ref || destination?.ref != deskDestination?.ref {
            deskLost()
        }
        if deskSource == nil, let source, let destination {
            deskSource = source
            deskDestination = destination
            status.deskName = source.displayName
            status.desk = .standby
            needsClean = true
            deskReleasedAt = Date()
            settleAnnounced = false
            log("desk found: \(source.displayName)")
        } else if deskSource == nil {
            status.desk = .notFound
        }
        let logicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: config.hostBundleID).isEmpty
        if logicRunning != status.logicRunning {
            status.logicRunning = logicRunning
            log(logicRunning ? "\(status.hostName) is running" : "\(status.hostName) is not running; the desk stays in standby until it starts")
            if !logicRunning {
                // Whatever was wrong with Logic's ports goes with it.
                logicPortsLostAt = nil
                probeSentAt = nil
                status.logicDeaf = false
            }
        }
        status.midiServerRestartedAt = logicRunning ? logicPortsLostAt : nil
        if let stream = deskAudio.checkStream() { log(stream) }
        if logicRunning, let lost = logicPortsLostAt, lastProbeAt < lost {
            announceToLogic()   // the one way to find out whether Logic still hears the bridge
        }
        if let sent = probeSentAt, logicRunning, Date().timeIntervalSince(sent) > Self.probeAnswerSeconds {
            probeSentAt = nil
            if !status.logicDeaf {
                status.logicDeaf = true
                if let lost = logicPortsLostAt {
                    report("\(status.hostName) has not answered the bridge: its MIDI ports went with the MIDI server at \(Self.clock(lost)). Quit \(status.hostName) and open it again")
                } else {
                    report("\(status.hostName) is running but has not answered the bridge: check that a project is open, that the Mackie Control's ports are \"\(Self.virtualPortName)\", and that \"\(Self.virtualPortName)\" is ticked in Settings > MIDI > Inputs")
                }
            }
        }
        status.lastMessageAt = lastFromLogic == .distantPast ? nil : lastFromLogic
        let wantDesk = deskSource != nil && !deskConnected && (logicRunning || needsClean)
        let settleLeft = Self.settleSeconds - Date().timeIntervalSince(deskReleasedAt)
        if wantDesk, settleLeft > 0 {
            status.desk = .settling
            if !settleAnnounced {
                settleAnnounced = true
                log("letting the desk settle for \(Int(settleLeft.rounded(.up))) s before connecting")
            }
        } else if wantDesk {
            // A desk just found with Logic closed may still show whatever was last written
            // to it (the driver wakes it briefly when it loads), so it is wiped once.
            connectDesk(toClean: !logicRunning)
        }
        if !logicRunning, deskConnected, !cleaning { disconnectDesk() }
        status.logicTalking = logicRunning && Date().timeIntervalSince(lastFromLogic) < Self.logicSilentSeconds
    }

    /// Whether the desk has yet to be wiped since it was found (see `check`).
    private var needsClean = false
    /// The current connection exists only to wipe the desk and release it again.
    private var cleaning = false

    private func connectDesk(toClean: Bool = false) {
        guard let deskSource, !deskConnected else { return }
        cleaning = toClean
        do {
            let connection = try MIDIConnection(name: "003 bridge desk")
            try connection.listen(to: deskSource) { [weak self] _, bytes in
                self?.queue.async { self?.receiveFromDesk(bytes) }
            }
            deskConnection = connection
        } catch {
            report("could not connect to the desk: \(error)")
            return
        }
        deskConnected = true
        deskAwake = false
        deskDeaf = false
        stuckDetector = StuckDetector()
        status.desk = .waking
        wakeGeneration += 1
        let generation = wakeGeneration
        log("desk connected\(toClean ? " to wipe it" : ""), waiting \(config.deskWakeSeconds) s for it to wake")
        holdAudio()
        queue.asyncAfter(deadline: .now() + config.deskWakeSeconds) { [weak self] in
            guard let self, self.deskConnected, generation == self.wakeGeneration else { return }
            self.deskAwake = true
            if self.cleaning {
                self.disconnectDesk()        // wipes it on the way out
                return
            }
            self.status.desk = .connected
            self.status.stuckAt = nil
            self.replayState(generation: generation)
            self.announceToLogic()
            // The desk has dropped a replay sent the moment it woke, so it is sent again.
            self.queue.asyncAfter(deadline: .now() + Self.replayRepeatSeconds) { [weak self] in
                guard let self, self.deskAwake, generation == self.wakeGeneration else { return }
                self.replayState(generation: generation)
            }
        }
    }

    /// Keeps the desk's audio engine running for as long as the bridge is connected, or
    /// says why nothing will reach the desk if that is turned off.
    private func holdAudio() {
        guard let device = DeskAudio.findDevice() else {
            log("the desk's audio device was not found; MIDI to the desk needs its audio engine running")
            return
        }
        let running = DeskAudio.isRunning(device)
        guard config.holdAudioEngine else {
            if !running {
                log("warning: nothing is running the desk's audio engine, so nothing sent to the desk will arrive until something does (Settings > Keep the desk's audio engine running)")
            } else {
                log("the desk's audio engine is running (another program holds it); MIDI to the desk rides on it")
            }
            return
        }
        guard !deskAudio.holding else { return }
        do {
            try deskAudio.start()
            log(running ? "desk audio engine held (something else was running it too)" : "desk audio engine started; MIDI to the desk rides on it")
        } catch {
            report("could not run the desk's audio engine: \(error); MIDI to the desk may not get through")
        }
    }

    private func releaseAudio() {
        guard deskAudio.holding else { return }
        deskAudio.stop()
        log("desk audio engine released")
    }

    /// A fader sprang back after it was released (see `StuckDetector`). One can be a
    /// fluke; two within a minute mean the desk has stopped taking commands.
    private func noteSnapBack(_ snapBack: StuckDetector.SnapBack) {
        let now = Date()
        log("fader \(snapBack.channel + 1) sprang back from \(snapBack.released) to \(snapBack.reported) after it was released: the desk did not take the position it was given")
        stuckStrikes = stuckStrikes.filter { now.timeIntervalSince($0) < Self.stuckStrikeWindowSeconds } + [now]
        guard stuckStrikes.count >= Self.stuckStrikesNeeded else { return }
        stuckStrikes = []
        deskStuck(at: now)
    }

    /// The desk has stopped following. A reconnect clears it (Avid's driver stops and
    /// starts the desk's surface link as the client goes and comes back), so that is done
    /// by itself unless the setting is off or it keeps happening.
    private func deskStuck(at now: Date) {
        stuckReconnects = stuckReconnects.filter { now.timeIntervalSince($0) < Self.stuckReconnectWindowSeconds }
        if config.reconnectWhenStuck, stuckReconnects.count < Self.stuckReconnectsBeforeGivingUp {
            stuckReconnects.append(now)
            status.stuckAt = now
            report("the desk has stopped following \(status.hostName) (faders spring back when released): reconnecting it")
            disconnectDesk(wipe: false, toReconnect: true)
        } else {
            status.desk = .notFollowing
            status.stuckAt = now
            report(config.reconnectWhenStuck
                ? "the desk has stopped following \(status.hostName) again, after \(stuckReconnects.count) reconnects in \(Int(Self.stuckReconnectWindowSeconds / 60)) min: switch it off, wait for \"not found\", and switch it on"
                : "the desk has stopped following \(status.hostName) (faders spring back when released): use Reconnect Desk, or switch it off and on")
        }
    }

    /// Sends everything the bridge knows, a few milliseconds apart so a just-woken desk
    /// keeps up. Each command is skipped if the desk was disconnected in the meantime.
    private func replayState(generation: Int) {
        let commands = bridge.startup()
        log("desk awake, sending \(commands.count) state commands")
        for (i, command) in commands.enumerated() {
            queue.asyncAfter(deadline: .now() + Double(i) * Self.replaySpacingSeconds) { [weak self] in
                guard let self, self.deskAwake, generation == self.wakeGeneration else { return }
                self.emit([command])
            }
        }
    }

    /// Tells Logic a surface has just appeared, so it re-sends its whole state. Needed
    /// when the bridge starts while Logic is already open; harmless otherwise.
    private func announceToLogic() {
        sendToLogic(.connectionQuery(serial: Self.serial, challenge: Self.challenge))
        let now = Date()
        lastProbeAt = now
        if probeSentAt == nil { probeSentAt = now }
        log("announced the surface to \(status.hostName)")
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    public static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    private func sendToLogic(_ message: MCUMessage) {
        do { try logicPort?.send(MCUEncoder.encode(message)) } catch { report("to Logic failed: \(error)") }
    }

    /// Blanks every display, LED and ring and parks the faders. The desk keeps whatever
    /// was last written to it and shows that again when it next wakes, so this is done
    /// before it is released. Sent with a short gap so nothing is dropped.
    private func clearDesk() {
        guard deskAwake else { return }
        for command in Bridge(config: config).startup() {
            emit([command])
            usleep(UInt32(Self.replaySpacingSeconds * 1_000_000))
        }
    }

    /// The desk's ports have gone: it was switched off or unplugged. The connection is
    /// dropped as it stands (there is nothing left to wipe) and the search starts again,
    /// so the desk is picked up and wiped or filled in when it comes back.
    private func deskLost() {
        let name = deskSource?.displayName ?? "desk"
        if deskConnected { disconnectDesk(wipe: false) }
        deskSource = nil
        deskDestination = nil
        needsClean = false
        deskDeaf = false
        status.desk = .notFound
        log("desk lost: \(name) is off or unplugged; waiting for it to come back")
    }

    private func disconnectDesk(wipe: Bool = true, toReconnect: Bool = false) {
        guard deskConnected else { return }
        if wipe { clearDesk() }
        // Releasing the desk takes the source disconnect, the ports and the client going,
        // explicitly and in that order; just dropping the reference left the desk awake.
        deskConnection?.close()
        deskConnection = nil
        deskConnected = false
        deskAwake = false
        deskReleasedAt = Date()
        settleAnnounced = false
        let wasCleaning = cleaning
        cleaning = false
        needsClean = false
        bridge = Bridge(config: config)  // Logic's state went with it
        surfaceDecoder = SurfaceDecoder()
        onSurface?(bridge.startup())
        if status.desk != .notFound { status.desk = .standby }
        if toReconnect { log("desk disconnected to take it afresh once it has settled") }
        else if !wipe { log("desk disconnected without a wipe; its ports are gone") }
        else if wasCleaning { log("desk wiped and released; it goes back to standby") }
        else { log("desk wiped and disconnected; it goes back to standby") }
        // The wipe is still on its way through the driver; the engine carries it first.
        queue.asyncAfter(deadline: .now() + (wipe ? Self.audioReleaseSeconds : 0)) { [weak self] in
            guard let self, !self.deskConnected else { return }
            self.releaseAudio()
        }
    }

    // MARK: Traffic

    private func receiveFromDesk(_ bytes: [UInt8]) {
        var sentToLogic = false
        let now = Date()
        for event in surfaceDecoder.decode(bytes) {
            if deskAwake { stuckDetector.surface(event, at: now) }
            let out = bridge.fromSurface(event)
            trace("desk -> \(event) => Logic \(out.toLogic)")
            deliver(out)
            sentToLogic = sentToLogic || !out.toLogic.isEmpty
        }
        // Desk events going to a Logic that has said nothing for a while: announce the
        // surface again, which a live Logic answers at once and a deaf one never does.
        if sentToLogic, status.logicRunning, probeSentAt == nil,
           now.timeIntervalSince(lastFromLogic) > Self.probeSilentSeconds,
           now.timeIntervalSince(lastProbeAt) > Self.probeRepeatSeconds {
            announceToLogic()
        }
    }

    private func receiveFromLogic(_ bytes: [UInt8]) {
        lastFromLogic = Date()
        probeSentAt = nil
        if status.logicDeaf {
            status.logicDeaf = false
            log("\(status.hostName) is answering again")
        }
        if logicPortsLostAt != nil {
            logicPortsLostAt = nil     // it got through, so Logic has new ports
            status.midiServerRestartedAt = nil
        }
        let messages = mcuDecoder.decode(bytes)
        if messages.isEmpty {
            trace("Logic -> (unhandled) \(Hex.format(bytes))")
        }
        for message in messages {
            // The handshake is the service's business, not the translator's.
            switch message {
            case .deviceQuery:
                if deskAwake, Date().timeIntervalSince(lastProbeAt) > Self.announceGapSeconds {
                    trace("Logic -> device query")
                    announceToLogic()
                } else {
                    trace("Logic -> device query (\(deskAwake ? "just answered" : "desk not awake yet"))")
                }
                continue
            case .hostConnectionReply:
                sendToLogic(.connectionConfirmation(serial: Self.serial))
                log("Logic accepted the surface")
                continue
            case .versionRequest:
                // Part of Logic's start-up scan; a surface that stays silent here gets
                // no state from Logic until its port is recreated.
                sendToLogic(.versionReply(Self.version))
                trace("Logic -> version request, answered \(Self.version)")
                continue
            default:
                break
            }
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
            queue.asyncAfter(deadline: .now() + config.valueDisplaySeconds) { [weak self] in
                guard let self else { return }
                self.emit(self.bridge.revertDisplay(revert))
            }
        }
        emit(out.toSurface)
    }

    /// Commands for the desk: shown to whoever watches (`onSurface`) and sent if the desk
    /// is awake. Before it is awake they are dropped here; `replayState` catches it up.
    private func emit(_ commands: [SurfaceCommand]) {
        guard !commands.isEmpty else { return }
        onSurface?(commands)
        if deskAwake { sendToDesk(commands) }
    }

    private func sendToDesk(_ commands: [SurfaceCommand]) {
        guard deskConnected, !deskDeaf, let connection = deskConnection, let deskDestination else { return }
        for command in commands {
            stuckDetector.sent(command)
            let bytes = SurfaceEncoder.encode(command)
            let started = Date()
            do { try connection.send(bytes, to: deskDestination) } catch { report("to desk failed: \(error)") }
            let took = Date().timeIntervalSince(started)
            if took > Self.slowSendSeconds {
                // The driver only blocks the sender once its buffer to the desk is full and
                // the desk is not emptying it. Nothing more is sent, so the buffer can drain
                // and the desk can be switched off without taking the MIDI server down.
                deskDeaf = true
                status.desk = .deaf
                report(String(format: "the desk is not taking commands (a message took %.1f s to go): switch the desk off, wait for \"not found\", and switch it on; the bridge then reconnects and refills it", took))
                return
            }
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
