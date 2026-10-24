import AppKit
import BridgeRuntime
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let service = BridgeService(verbose: false)
    private var window: NSWindow!
    private var statusItem: NSStatusItem!

    private let deskLabel = NSTextField(labelWithString: "")
    private let logicLabel = NSTextField(labelWithString: "")
    private let bridgeLabel = NSTextField(labelWithString: "")
    private let helpLabel = NSTextField(wrappingLabelWithString: "")
    private let startStopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let restartButton = NSButton(title: "Restart", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)
    private let logView = NSTextView()
    private var logLines: [String] = []
    private let maxLogLines = 500

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        buildWindow()
        buildStatusItem()
        service.onStatus = { [weak self] status in
            DispatchQueue.main.async { self?.show(status) }
        }
        service.onLog = { [weak self] line in
            DispatchQueue.main.async { self?.appendLog(line) }
        }
        startService()
        show(service.status)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
    }

    // MARK: Actions

    @objc private func toggleService(_ sender: Any?) {
        if service.status.running { service.stop() } else { startService() }
    }

    @objc private func restartService(_ sender: Any?) {
        do { try service.restart() } catch { appendLog("restart failed: \(error)") }
    }

    @objc private func showWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLogin(_ sender: Any?) {
        guard #available(macOS 13, *) else { return }
        do {
            if loginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            appendLog("start at login: \(error.localizedDescription)")
        }
        refreshLoginCheckbox()
    }

    @objc private func copyLog(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logLines.joined(separator: "\n"), forType: .string)
    }

    private func startService() {
        do { try service.start() } catch { appendLog("start failed: \(error)") }
    }

    // MARK: Status

    private func show(_ status: BridgeService.Status) {
        let desk: String
        switch status.desk {
        case .notFound: desk = "Not found. Is the desk on, and is the Avid 003 Family driver installed?"
        case .standby: desk = "\(status.deskName): in standby until Logic runs"
        case .waking: desk = "\(status.deskName): waking up"
        case .connected: desk = "\(status.deskName): connected"
        }
        deskLabel.stringValue = "Desk: " + desk
        logicLabel.stringValue = "Logic Pro: " + (status.logicRunning
            ? (status.logicTalking ? "running and talking to the bridge" : "running")
            : "not running")
        bridgeLabel.stringValue = "Bridge: " + (status.running ? "running" : "stopped")
            + (status.lastError.map { " (last error: \($0))" } ?? "")
        startStopButton.title = status.running ? "Stop" : "Start"
        restartButton.isEnabled = status.running

        if status.running, status.logicRunning, !status.logicTalking {
            helpLabel.stringValue = """
                Logic is running but has not sent anything to the bridge. Set it up once in Logic: \
                Control Surfaces > Setup > New > Install > Mackie Designs > Mackie Control, \
                then set the surface's Output Port and Input Port to "\(BridgeService.virtualPortName)". \
                Logic needs a project open to send its state.
                """
        } else if !status.running {
            helpLabel.stringValue = "Press Start to bring up the \"\(BridgeService.virtualPortName)\" port."
        } else {
            helpLabel.stringValue = "Open Logic and the desk wakes up; quit Logic and it goes back to standby."
        }
        updateStatusMenu(status)
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > maxLogLines { logLines.removeFirst(logLines.count - maxLogLines) }
        logView.string = logLines.joined(separator: "\n")
        logView.scrollToEndOfDocument(nil)
    }

    private func refreshLoginCheckbox() {
        if #available(macOS 13, *) {
            loginCheckbox.isEnabled = Bundle.main.bundleIdentifier != nil
            loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            loginCheckbox.toolTip = loginCheckbox.isEnabled ? nil : "Only available when run as 002 Bridge.app"
        } else {
            loginCheckbox.isEnabled = false
            loginCheckbox.toolTip = "Needs macOS 13 or later; use tools/install.sh --login instead"
        }
    }

    // MARK: Building the UI

    private func buildMenus() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About 002 Bridge", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide 002 Bridge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit 002 Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let bridgeMenu = NSMenu(title: "Bridge")
        bridgeMenu.addItem(withTitle: "Restart Bridge", action: #selector(restartService(_:)), keyEquivalent: "r")
        bridgeMenu.addItem(withTitle: "Copy Log", action: #selector(copyLog(_:)), keyEquivalent: "c")
        let bridgeItem = NSMenuItem()
        bridgeItem.submenu = bridgeMenu
        mainMenu.addItem(bridgeItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "002 Bridge", action: #selector(showWindow(_:)), keyEquivalent: "0")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "002 Bridge"
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
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin(_:))
        refreshLoginCheckbox()
        let buttons = NSStackView(views: [startStopButton, restartButton, NSView(), loginCheckbox])
        buttons.orientation = .horizontal

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = true
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = false
        logView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let logTitle = NSTextField(labelWithString: "Log")
        logTitle.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [deskLabel, logicLabel, bridgeLabel, helpLabel, buttons, logTitle, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [deskLabel, logicLabel, bridgeLabel, helpLabel, buttons, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        window.contentView = stack
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "002"
        statusItem.button?.toolTip = "002 Bridge"
        let menu = NSMenu()
        menu.addItem(withTitle: "Desk", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Logic", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Restart Bridge", action: #selector(restartService(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open 002 Bridge", action: #selector(showWindow(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    private func updateStatusMenu(_ status: BridgeService.Status) {
        guard let items = statusItem?.menu?.items, items.count >= 2 else { return }
        items[0].title = deskLabel.stringValue
        items[1].title = logicLabel.stringValue
        items[0].isEnabled = false
        items[1].isEnabled = false
        let dot: String
        switch status.desk {
        case .connected: dot = "002 ●"
        case .waking, .standby: dot = "002 ○"
        case .notFound: dot = "002 ✕"
        }
        statusItem.button?.title = status.running ? dot : "002 –"
    }
}
