import AppKit
import BridgeCore
import BridgeRuntime
import Digi00x

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let configOutcome = ConfigFile.load()
    // Detailed by default: every translated message goes to the log file, which is what
    // makes a "the faders did not move" report diagnosable after the event.
    private lazy var service = BridgeService(verbose: true, config: ConfigFile.config(from: configOutcome))
    private lazy var settings = SettingsWindowController(config: service.config)
    private let notifier = Notifier()
    /// ~/Library/Logs/002 Bridge.log, started fresh on each launch; the previous launch's
    /// log is kept as "002 Bridge.previous.log".
    private var logFile: FileHandle?
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/002 Bridge.log")
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var clock: Timer?

    private let deskLabel = NSTextField(labelWithString: "")
    private let logicLabel = NSTextField(labelWithString: "")
    private let bridgeLabel = NSTextField(labelWithString: "")
    private let helpLabel = NSTextField(wrappingLabelWithString: "")
    private let deskView = DeskView()
    private var deskHeight: NSLayoutConstraint!
    private let startStopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let restartButton = NSButton(title: "Restart", target: nil, action: nil)
    private let reconnectButton = NSButton(title: "Reconnect Desk", target: nil, action: nil)
    private let logView = NSTextView()
    private let logTitle = NSTextField(labelWithString: "Log")
    private let logScroll = NSScrollView()
    private var stack: NSStackView!
    /// The window's height with the log shown, kept while the log is hidden.
    private var heightWithLog: CGFloat = 0
    private var logLines: [String] = []
    private let maxLogLines = 500
    private var lastStatus = BridgeService.Status()
    /// The host launch (by its start time) already warned about for sending nothing.
    private var silentWarnedFor: Date?
    static let silentWarningSeconds = 20.0

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.register()
        service.verbose = Preferences.bool(Preferences.debugLog)
        openLogFile()
        switch configOutcome {
        case .defaults: appendLog("settings: defaults (no file at \(ConfigFile.url.path))")
        case .loaded: appendLog("settings: \(ConfigFile.url.path)")
        case let .invalid(reason): appendLog("settings: could not read \(reason); using defaults")
        }
        applyDockPreference()
        buildMenus()
        buildWindow()
        buildStatusItem()
        settings.onConfigChange = { [weak self] config in self?.saveAndApply(config) }
        settings.onPreferenceChange = { [weak self] in self?.preferencesChanged() }
        settings.onPictureChange = { [weak self] in self?.loadDeskPicture() }
        service.onStatus = { [weak self] status in
            DispatchQueue.main.async { self?.show(status) }
        }
        service.onLog = { [weak self] line in
            // The file is written here, on the service's queue, so the last lines of a
            // quit (the desk being wiped and released) are in it; the window follows.
            self?.writeLog(line)
            DispatchQueue.main.async { self?.appendLog(line, toFile: false) }
        }
        service.onSurface = { [weak self] commands in
            DispatchQueue.main.async { self?.deskView.apply(commands) }
        }
        show(service.status)
        startService()
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.everySecond() }
        window.makeKeyAndOrderFront(nil)
        setLogVisible(Preferences.bool(Preferences.debugLog))
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
    }

    // MARK: Actions

    @objc private func toggleService(_ sender: Any?) {
        if service.status.running { stopService() } else { startService() }
    }

    @objc private func restartService(_ sender: Any?) {
        stopService()
        startService()
    }

    @objc private func reconnectDesk(_ sender: Any?) {
        service.reconnectDesk()
    }

    /// Restarts the Mac's MIDI server (MIDIServer, which hosts Avid's driver) and the
    /// bridge. The server can wedge inside the Avid driver after the desk is power cycled:
    /// every program using MIDI then blocks and nothing reaches the desk. It restarts on
    /// demand, so killing it is safe; other MIDI apps reconnect by themselves, though
    /// Logic may need to be reopened.
    @objc private func resetMIDIServer(_ sender: Any?) {
        appendLog("resetting the MIDI server")
        stopService()
        work.async { [weak self] in
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            kill.arguments = ["MIDIServer"]
            try? kill.run()
            kill.waitUntilExit()
            Thread.sleep(forTimeInterval: 2)
            DispatchQueue.main.async { self?.startService() }
        }
    }

    @objc private func showWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings(_ sender: Any?) {
        settings.config = service.config
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHost(_ sender: Any?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: service.config.hostBundleID) else {
            appendLog("\(service.status.hostName) is not installed (\(service.config.hostBundleID))")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func copyLog(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logLines.joined(separator: "\n"), forType: .string)
    }

    @objc private func showLogFile(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([Self.logURL])
    }

    @objc private func showHelp(_ sender: Any?) {
        if let url = Bundle.main.url(forResource: "user-guide", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/craigmillard86/Digi002-Bridge")!)
        }
    }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
        let driverPlist = "/Library/Audio/MIDI Drivers/Avid 003 Family.plugin/Contents/Info.plist"
        let driver = (NSDictionary(contentsOfFile: driverPlist)?["CFBundleShortVersionString"] as? String).map { "Avid 003 Family driver \($0)" }
            ?? "Avid 003 Family driver not found"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let lines = [
            "Bridges a Digi 002 control surface to Logic Pro as a Mackie Control.",
            "",
            driver,
            "macOS \(os)",
            "Desk: \(service.status.deskName.isEmpty ? "not found" : service.status.deskName)",
            "Log: \(Self.logURL.path)",
            "Settings: \(ConfigFile.url.path)",
        ]
        let credits = NSAttributedString(string: lines.joined(separator: "\n"),
                                         attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "002 Bridge",
                                                     .applicationVersion: version,
                                                     .credits: credits])
    }

    /// CoreMIDI calls block for as long as the MIDI server takes to answer, which is for
    /// ever when it has wedged, so the service is started and stopped off the main thread
    /// and the window stays usable (and "Reset MIDI Server" stays reachable).
    private let work = DispatchQueue(label: "bridge.control")

    private func startService() {
        work.async { [weak self] in
            guard let self else { return }
            do { try self.service.start() } catch {
                DispatchQueue.main.async { self.appendLog("start failed: \(error)") }
            }
        }
    }

    private func stopService() {
        work.async { [weak self] in self?.service.stop() }
    }

    /// Picks up desk.png and desk-layout.json (Application Support, else the bundle).
    func loadDeskPicture() {
        deskView.picture = DeskPicture.load()
        deskHeight.constant = deskView.height(forWidth: 548)
    }

    // MARK: Settings

    private func saveAndApply(_ config: BridgeConfig) {
        do { try ConfigFile.save(config) } catch { appendLog("could not save settings: \(error.localizedDescription)") }
        service.apply(config)
    }

    private func preferencesChanged() {
        let debug = Preferences.bool(Preferences.debugLog)
        if debug != service.verbose {
            service.verbose = debug
            appendLog(debug ? "debug log on: every message is logged" : "debug log off: only state changes and errors are logged")
        }
        setLogVisible(debug)
        applyDockPreference()
    }

    /// The log pane goes with the debug log: without it the window is just the status and
    /// the desk, sized to fit. The log file is written either way.
    private func setLogVisible(_ visible: Bool) {
        guard logScroll.isHidden == visible else { return }
        logTitle.isHidden = !visible
        logScroll.isHidden = !visible
        var frame = window.frame
        let height: CGFloat
        if visible {
            height = max(heightWithLog, Self.minHeightWithLog)
            window.minSize = NSSize(width: Self.minWidth, height: Self.minHeightWithLog)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        } else {
            heightWithLog = frame.height
            stack.layoutSubtreeIfNeeded()
            let content = NSRect(x: 0, y: 0, width: frame.width, height: stack.fittingSize.height)
            height = window.frameRect(forContentRect: content).height
            window.minSize = NSSize(width: Self.minWidth, height: height)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: height)
        }
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }

    static let minWidth: CGFloat = 580
    static let minHeightWithLog: CGFloat = 480

    private func applyDockPreference() {
        let hide = Preferences.bool(Preferences.hideDockIcon)
        let policy: NSApplication.ActivationPolicy = hide ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if !hide { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    // MARK: Status

    private static let clockFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func since(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        let age: String
        switch seconds {
        case ..<60: age = "\(seconds) s"
        case ..<3600: age = "\(seconds / 60) min"
        default: age = "\(seconds / 3600) h \(seconds % 3600 / 60) min"
        }
        return " since \(clockFormat.string(from: date)) (\(age))"
    }

    private func show(_ status: BridgeService.Status) {
        let desk: String
        switch status.desk {
        case .notFound: desk = "not found" + Self.since(status.deskChangedAt) + ". Is the desk on, and is the Avid 003 Family driver installed?"
        case .standby: desk = "\(status.deskName): in standby" + Self.since(status.deskChangedAt)
        case .settling where status.stuckAt != nil:
            desk = "\(status.deskName): stopped following at \(BridgeService.clock(status.stuckAt!)), connecting again in a moment"
        case .waking where status.stuckAt != nil:
            desk = "\(status.deskName): stopped following at \(BridgeService.clock(status.stuckAt!)), waking up again"
        case .settling: desk = "\(status.deskName): found, connecting in a moment"
        case .waking: desk = "\(status.deskName): waking up"
        case .connected: desk = "\(status.deskName): connected" + Self.since(status.deskChangedAt)
        case .deaf: desk = "\(status.deskName): NOT taking commands. Switch the desk off, wait for \"not found\", switch it on"
        case .notFollowing: desk = "\(status.deskName): NOT following \(status.hostName)" + Self.since(status.deskChangedAt)
            + ". Use Reconnect Desk, or switch the desk off, wait for \"not found\", switch it on"
        }
        deskLabel.stringValue = "Desk: " + desk
        var logic = status.logicRunning ? "running" + Self.since(status.logicChangedAt) : "not running" + Self.since(status.logicChangedAt)
        if status.logicRunning {
            if let last = status.lastMessageAt {
                let age = Int(Date().timeIntervalSince(last))
                logic += status.logicTalking ? ", talking to the bridge" : ", last message \(age < 60 ? "\(age) s" : "\(age / 60) min") ago"
            } else {
                logic += ", nothing received yet"
            }
            if status.logicDeaf {
                logic += status.midiServerRestartedAt != nil ? ". NOT answering: quit it and open it again" : ". NOT answering the bridge"
            }
        }
        logicLabel.stringValue = "\(status.hostName): " + logic
        bridgeLabel.stringValue = "Bridge: " + (status.running ? "running" : "stopped")
            + (status.lastError.map { " (last error: \($0))" } ?? "")
        startStopButton.title = status.running ? "Stop" : "Start"
        restartButton.isEnabled = status.running
        reconnectButton.isEnabled = status.running && status.desk != .notFound

        if status.running, status.logicRunning, let lost = status.midiServerRestartedAt {
            helpLabel.stringValue = """
                The MIDI server restarted at \(BridgeService.clock(lost)) while \(status.hostName) was open, so \(status.hostName) \
                lost its MIDI ports and cannot hear or reach the bridge. Quit \(status.hostName) and open it again; \
                the desk refills by itself.
                """
        } else if status.running, status.logicRunning, !status.logicTalking {
            helpLabel.stringValue = """
                \(status.hostName) is running but has not sent anything to the bridge. Set it up once: \
                Control Surfaces > Setup > New > Install > Mackie Designs > Mackie Control, \
                set the surface's Output Port and Input Port to "\(BridgeService.virtualPortName)", \
                and tick "\(BridgeService.virtualPortName)" in Settings > MIDI > Inputs. A project must be open.
                """
        } else if !status.running {
            helpLabel.stringValue = "Press Start to bring up the \"\(BridgeService.virtualPortName)\" port."
        } else {
            helpLabel.stringValue = "Open \(status.hostName) and the desk wakes up; quit it and the desk goes back to standby."
        }
        updateStatusMenu(status)
        notice(from: lastStatus, to: status)
        lastStatus = status
    }

    /// Notifications and sounds for the transitions worth hearing about.
    private func notice(from old: BridgeService.Status, to new: BridgeService.Status) {
        guard old.running, new.running else { return }   // start and stop are the user's doing
        if old.desk != .notFound, new.desk == .notFound {
            Preferences.play(Preferences.lostSound)
            if Preferences.bool(Preferences.notifyDeskLost) {
                notifier.post("Desk lost", "\(old.deskName) is off or unplugged. The bridge reconnects when it is back.")
            }
        }
        if old.desk != .deaf, new.desk == .deaf {
            Preferences.play(Preferences.lostSound)
            if Preferences.bool(Preferences.notifyDeskLost) {
                notifier.post("Desk not responding", "\(new.deskName) is not taking commands. Switch it off, wait for \"not found\", and switch it on.")
            }
        }
        if old.stuckAt == nil, let at = new.stuckAt {
            Preferences.play(Preferences.lostSound)
            if Preferences.bool(Preferences.notifyDeskLost) {
                let what = "\(new.deskName) stopped taking commands at \(BridgeService.clock(at)): its faders spring back when released."
                notifier.post("Desk stopped following",
                              new.desk == .notFollowing
                                ? what + " Use Reconnect Desk, or switch it off and on."
                                : what + " The bridge is reconnecting it.")
            }
        }
        if old.desk != .connected, new.desk == .connected {
            Preferences.play(Preferences.connectSound)
            if Preferences.bool(Preferences.notifyDeskBack) {
                notifier.post("Desk connected", "\(new.deskName) is awake and following \(new.hostName).")
            }
        }
        if !old.logicDeaf, new.logicDeaf {
            Preferences.play(Preferences.lostSound)
            if Preferences.bool(Preferences.notifyLogicSilent) {
                if new.midiServerRestartedAt != nil {
                    notifier.post("\(new.hostName) needs reopening",
                                  "The MIDI server restarted while \(new.hostName) was open, so it lost its MIDI ports. Quit it and open it again.")
                } else {
                    notifier.post("\(new.hostName) is not answering",
                                  "The bridge announced the desk and nothing came back. Open a project, and check the Mackie Control setup and MIDI inputs.")
                }
            }
        }
        if !new.logicRunning { silentWarnedFor = nil }
    }

    /// Ages in the labels, and the one warning that needs a clock: the host has been
    /// running for a while and sent nothing, which means it is not set up for the port.
    private func everySecond() {
        // The copy from the last status callback: the service's own is only read on its queue.
        let status = lastStatus
        show(status)
        guard status.running, status.logicRunning, !status.logicTalking, status.lastMessageAt == nil,
              let started = status.logicChangedAt, Date().timeIntervalSince(started) > Self.silentWarningSeconds,
              silentWarnedFor != started else { return }
        silentWarnedFor = started
        appendLog("\(status.hostName) has sent nothing for \(Int(Self.silentWarningSeconds)) s: check its Mackie Control setup and MIDI inputs, and that a project is open")
        if Preferences.bool(Preferences.notifyLogicSilent) {
            notifier.post("\(status.hostName) is ignoring the desk",
                          "Nothing has arrived on \"\(BridgeService.virtualPortName)\". Check the Mackie Control setup and MIDI inputs, or open a project.")
        }
    }

    private func openLogFile() {
        let url = Self.logURL
        let previous = url.deletingPathExtension().appendingPathExtension("previous.log")
        let files = FileManager.default
        try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? files.removeItem(at: previous)
        try? files.moveItem(at: url, to: previous)
        files.createFile(atPath: url.path, contents: nil)
        logFile = try? FileHandle(forWritingTo: url)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        appendLog("002 Bridge \(version) started \(Date()); log file \(url.path); debug log \(service.verbose ? "on" : "off")")
    }

    /// Serialises writes from the service's queue and the main thread.
    private let logQueue = DispatchQueue(label: "bridge.log")

    private func writeLog(_ line: String) {
        logQueue.sync { logFile?.write(Data((line + "\n").utf8)) }
    }

    private func appendLog(_ line: String, toFile: Bool = true) {
        if toFile { writeLog(line) }
        logLines.append(line)
        // Appending keeps the window responsive with traffic logged; the view is only
        // rebuilt when old lines are dropped.
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
            logView.string = logLines.joined(separator: "\n")
        } else {
            logView.textStorage?.append(NSAttributedString(string: (logLines.count > 1 ? "\n" : "") + line,
                                                           attributes: [.font: logView.font ?? .systemFont(ofSize: 11)]))
        }
        logView.scrollToEndOfDocument(nil)
    }

    // MARK: Building the UI

    private func buildMenus() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About 002 Bridge", action: #selector(showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide 002 Bridge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit 002 Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let bridgeMenu = NSMenu(title: "Bridge")
        bridgeMenu.addItem(withTitle: "Start / Stop Bridge", action: #selector(toggleService(_:)), keyEquivalent: "")
        bridgeMenu.addItem(withTitle: "Restart Bridge", action: #selector(restartService(_:)), keyEquivalent: "r")
        bridgeMenu.addItem(withTitle: "Reconnect Desk", action: #selector(reconnectDesk(_:)), keyEquivalent: "d")
        bridgeMenu.addItem(withTitle: "Reset MIDI Server", action: #selector(resetMIDIServer(_:)), keyEquivalent: "")
        bridgeMenu.addItem(.separator())
        bridgeMenu.addItem(withTitle: "Open Host Application", action: #selector(openHost(_:)), keyEquivalent: "o")
        bridgeMenu.addItem(.separator())
        let copy = bridgeMenu.addItem(withTitle: "Copy Log", action: #selector(copyLog(_:)), keyEquivalent: "c")
        copy.keyEquivalentModifierMask = [.command, .shift]
        bridgeMenu.addItem(withTitle: "Show Log File in Finder", action: #selector(showLogFile(_:)), keyEquivalent: "l")
        let bridgeItem = NSMenuItem()
        bridgeItem.submenu = bridgeMenu
        mainMenu.addItem(bridgeItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "002 Bridge", action: #selector(showWindow(_:)), keyEquivalent: "0")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "002 Bridge Button Guide", action: #selector(showHelp(_:)), keyEquivalent: "?")
        let helpItem = NSMenuItem()
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "002 Bridge"
        // Windows made in code are released when closed by default; this one is reopened
        // from the Dock and the menu bar, so it must stay around.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("main")

        for label in [deskLabel, logicLabel, bridgeLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
        }
        helpLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor

        startStopButton.target = self
        startStopButton.action = #selector(toggleService(_:))
        restartButton.target = self
        restartButton.action = #selector(restartService(_:))
        reconnectButton.target = self
        reconnectButton.action = #selector(reconnectDesk(_:))
        reconnectButton.toolTip = "Drop the desk connection and make it again"
        let settingsButton = NSButton(title: "Settings…", target: self, action: #selector(showSettings(_:)))
        let buttons = NSStackView(views: [startStopButton, restartButton, reconnectButton, NSView(), settingsButton])
        buttons.orientation = .horizontal

        deskView.toolTip = "What the bridge last sent to the desk"
        deskView.setContentHuggingPriority(.required, for: .vertical)

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = true
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = false
        logView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let scroll = logScroll
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        logTitle.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [deskLabel, logicLabel, bridgeLabel, helpLabel, deskView, buttons, logTitle, scroll])
        self.stack = stack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [deskLabel, logicLabel, bridgeLabel, helpLabel, deskView, buttons, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        deskHeight = deskView.heightAnchor.constraint(equalToConstant: DeskView.schematicHeight)
        deskHeight.isActive = true
        loadDeskPicture()
        window.contentView = stack
        window.minSize = NSSize(width: Self.minWidth, height: Self.minHeightWithLog)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "002"
        let menu = NSMenu()
        menu.addItem(withTitle: "Desk", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Logic", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reconnect Desk", action: #selector(reconnectDesk(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Restart Bridge", action: #selector(restartService(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Reset MIDI Server", action: #selector(resetMIDIServer(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Host Application", action: #selector(openHost(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Show Log File in Finder", action: #selector(showLogFile(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open 002 Bridge", action: #selector(showWindow(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit 002 Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    private func updateStatusMenu(_ status: BridgeService.Status) {
        guard let items = statusItem?.menu?.items, items.count >= 2 else { return }
        items[0].title = deskLabel.stringValue
        items[1].title = logicLabel.stringValue
        items[0].isEnabled = false
        items[1].isEnabled = false
        items[1].isHidden = false
        // A coloured dot says the state at a glance: green connected, orange found but
        // asleep, red not found, grey stopped.
        let colour: NSColor
        let state: String
        if !status.running {
            colour = .systemGray; state = "stopped"
        } else {
            if status.logicDeaf {
                colour = .systemRed
                state = status.midiServerRestartedAt != nil
                    ? "\(status.hostName) lost its MIDI ports: quit it and open it again"
                    : "\(status.hostName) is not answering the bridge"
            } else {
            switch status.desk {
            case .connected: colour = .systemGreen; state = "desk connected"
            case .waking, .settling: colour = .systemYellow; state = status.stuckAt == nil ? "desk waking" : "desk stopped following; reconnecting it"
            case .deaf: colour = .systemRed; state = "desk not taking commands: switch it off and on"
            case .notFollowing: colour = .systemRed; state = "desk not following: use Reconnect Desk, or switch it off and on"
            case .standby: colour = .systemOrange; state = "desk in standby"
            case .notFound: colour = .systemRed; state = "desk not found"
            }
            }
        }
        let title = NSMutableAttributedString(string: "002 ")
        title.append(NSAttributedString(string: "●", attributes: [.foregroundColor: colour]))
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = "002 Bridge: \(state)\n\(deskLabel.stringValue)\n\(logicLabel.stringValue)"
    }
}
