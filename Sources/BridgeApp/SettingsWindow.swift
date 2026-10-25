import AppKit
import BridgeCore
import BridgeRuntime
import ServiceManagement

/// The Settings window. Bridge settings go to the config file and take effect at once;
/// app settings go to UserDefaults. Everything is laid out in a grid, in code.
final class SettingsWindowController: NSWindowController {
    var config: BridgeConfig { didSet { if config != oldValue { load() } } }
    /// Called with every change the user makes to a bridge setting.
    var onConfigChange: ((BridgeConfig) -> Void)?
    /// Called after an app setting changed (Dock icon, debug log, login).
    var onPreferenceChange: (() -> Void)?
    /// Called after the desk picture was chosen or removed.
    var onPictureChange: (() -> Void)?

    private let loginBox = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)
    private let dockBox = NSButton(checkboxWithTitle: "Menu bar only (no Dock icon)", target: nil, action: nil)
    private let debugBox = NSButton(checkboxWithTitle: "Debug log (show the log in the window, and log every message)", target: nil, action: nil)
    private let wakeField = NSTextField(string: "")
    private let wakeStepper = NSStepper()
    private let valueField = NSTextField(string: "")
    private let valueStepper = NSStepper()
    private let inverseBox = NSButton(checkboxWithTitle: "Show changed values light-on-dark", target: nil, action: nil)
    private let namePopup = NSPopUpButton()
    private let scrollPopup = NSPopUpButton()
    private let timePopup = NSPopUpButton()
    private let meterBox = NSButton(checkboxWithTitle: "Rings show meters until Meter is pressed", target: nil, action: nil)
    private let nudgeBox = NSButton(checkboxWithTitle: "Nav pad moves by one track until Bank is pressed", target: nil, action: nil)
    private let armedBox = NSButton(checkboxWithTitle: "Record-armed tracks light SEL red as well", target: nil, action: nil)
    private var buttonPopups: [String: NSPopUpButton] = [:]
    private var shiftPopups: [String: NSPopUpButton] = [:]
    private let notifyLostBox = NSButton(checkboxWithTitle: "Desk switched off or lost", target: nil, action: nil)
    private let notifyBackBox = NSButton(checkboxWithTitle: "Desk back and connected", target: nil, action: nil)
    private let notifySilentBox = NSButton(checkboxWithTitle: "Host runs but ignores the surface (setup needed)", target: nil, action: nil)
    private let connectSoundPopup = NSPopUpButton()
    private let lostSoundPopup = NSPopUpButton()
    private let hostField = NSTextField(string: "")
    private var loading = false

    init(config: BridgeConfig) {
        self.config = config
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "002 Bridge Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        load()
        window.center()
        window.setFrameAutosaveName("settings")
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func row(_ title: String, _ view: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let stack = NSStackView(views: [label, view])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        return stack
    }

    private func numberRow(_ title: String, _ field: NSTextField, _ stepper: NSStepper, min: Double, max: Double, step: Double, unit: String) -> NSView {
        field.widthAnchor.constraint(equalToConstant: 50).isActive = true
        field.alignment = .right
        field.target = self
        field.action = #selector(changed(_:))
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = step
        stepper.target = self
        stepper.action = #selector(stepped(_:))
        let unitLabel = NSTextField(labelWithString: unit)
        let stack = NSStackView(views: [field, stepper, unitLabel])
        stack.orientation = .horizontal
        return row(title, stack)
    }

    private func build() {
        for box in [loginBox, dockBox, debugBox, inverseBox, meterBox, nudgeBox, armedBox,
                    notifyLostBox, notifyBackBox, notifySilentBox] {
            box.target = self
            box.action = #selector(changed(_:))
        }
        namePopup.addItems(withTitles: ["Pro Tools style (\"Audio 1\" is \"Aud1\")", "First four characters (\"Audi\")"])
        namePopup.target = self
        namePopup.action = #selector(changed(_:))
        scrollPopup.addItems(withTitles: ["Shortened", "Scroll through once, then shortened", "Keep scrolling"])
        timePopup.addItems(withTitles: ["Display 10: bar (or hours)",
                                        "Display 10: bar.beat (or hours.minutes)",
                                        "Displays 9 and 10: bar, then beat.division (or hours, then minutes.seconds)"])
        for popup in [scrollPopup, timePopup] {
            popup.target = self
            popup.action = #selector(changed(_:))
        }
        for popup in [connectSoundPopup, lostSoundPopup] {
            popup.addItems(withTitles: Preferences.sounds)
            popup.target = self
            popup.action = #selector(soundChanged(_:))
        }
        hostField.placeholderString = "com.apple.logic10"
        hostField.target = self
        hostField.action = #selector(changed(_:))
        hostField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let chooseHost = NSButton(title: "Choose App…", target: self, action: #selector(chooseHost(_:)))
        let hostRow = NSStackView(views: [hostField, chooseHost])
        hostRow.orientation = .horizontal

        var buttonRows: [NSView] = []
        for name in BridgeConfig.configurableButtons {
            let popup = NSPopUpButton()
            for action in ButtonAction.allCases {
                popup.addItem(withTitle: action.title)
                popup.lastItem?.representedObject = action.rawValue
            }
            popup.target = self
            popup.action = #selector(changed(_:))
            buttonPopups[name] = popup
            buttonRows.append(row(name, popup))
            let shiftPopup = NSPopUpButton()
            for action in ButtonAction.allCases {
                shiftPopup.addItem(withTitle: action == .none ? "Same as without Shift" : action.title)
                shiftPopup.lastItem?.representedObject = action.rawValue
            }
            shiftPopup.target = self
            shiftPopup.action = #selector(changed(_:))
            shiftPopups[name] = shiftPopup
            buttonRows.append(row("\(name) with Shift", shiftPopup))
        }

        let choosePicture = NSButton(title: "Choose Picture…", target: self, action: #selector(choosePicture(_:)))
        let removePicture = NSButton(title: "Use Schematic", target: self, action: #selector(removePicture(_:)))
        let showLayout = NSButton(title: "Show Layout File", target: self, action: #selector(showLayoutFile(_:)))
        let pictureRow = NSStackView(views: [choosePicture, removePicture, showLayout])
        pictureRow.orientation = .horizontal
        let pictureNote = NSTextField(wrappingLabelWithString:
            "A straight-down photo of the desk; the live faders, rings, displays and LEDs are drawn over it. Positions come from desk-layout.json next to it.")
        pictureNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pictureNote.textColor = .secondaryLabelColor

        let showConfig = NSButton(title: "Show Config File", target: self, action: #selector(showConfigFile(_:)))
        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaults(_:)))
        let footer = NSStackView(views: [showConfig, reset])
        footer.orientation = .horizontal

        let note = NSTextField(wrappingLabelWithString:
            "Changes apply at once. Bridge settings are kept in the config file, which the command line tool reads too.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor

        let views: [NSView] = [
            heading("General"), loginBox, dockBox, debugBox,
            heading("Desk"),
            numberRow("Wake wait:", wakeField, wakeStepper, min: 1, max: 30, step: 0.5, unit: "seconds after connecting"),
            numberRow("Value display:", valueField, valueStepper, min: 0.2, max: 10, step: 0.1, unit: "seconds before the name returns"),
            row("Track names:", namePopup), row("Long names:", scrollPopup), row("Position:", timePopup),
            inverseBox, meterBox, nudgeBox, armedBox,
            heading("Buttons"),
        ] + buttonRows + [
            heading("Notifications"), notifyLostBox, notifyBackBox, notifySilentBox,
            row("Sound on connect:", connectSoundPopup), row("Sound on loss:", lostSoundPopup),
            heading("Desk picture"), pictureRow, pictureNote,
            heading("Host application"), row("Bundle ID:", hostRow),
            footer, note,
        ]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for view in views where view is NSTextField && (view as! NSTextField).font?.fontDescriptor.symbolicTraits.contains(.bold) == true {
            stack.setCustomSpacing(10, after: view)
        }
        // Scrolls on a screen too short for the whole form.
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        window?.contentView = scroll
        let height = min(stack.fittingSize.height, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
        window?.setContentSize(NSSize(width: max(stack.fittingSize.width, 560), height: height))
    }

    // MARK: Loading and saving

    private func load() {
        loading = true
        defer { loading = false }
        if #available(macOS 13, *), Bundle.main.bundleIdentifier != nil {
            loginBox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            loginBox.isEnabled = false
            loginBox.toolTip = "Needs macOS 13 or later and the app bundle"
        }
        dockBox.state = Preferences.bool(Preferences.hideDockIcon) ? .on : .off
        debugBox.state = Preferences.bool(Preferences.debugLog) ? .on : .off
        wakeField.stringValue = String(format: "%.1f", config.deskWakeSeconds)
        wakeStepper.doubleValue = config.deskWakeSeconds
        valueField.stringValue = String(format: "%.1f", config.valueDisplaySeconds)
        valueStepper.doubleValue = config.valueDisplaySeconds
        inverseBox.state = config.valuesInverse ? .on : .off
        namePopup.selectItem(at: config.nameStyle == .proTools ? 0 : 1)
        scrollPopup.selectItem(at: BridgeConfig.NameScroll.allCases.firstIndex(of: config.nameScroll) ?? 0)
        timePopup.selectItem(at: BridgeConfig.TimeDisplay.allCases.firstIndex(of: config.timeDisplay) ?? 0)
        meterBox.state = config.meterModeAtStart ? .on : .off
        nudgeBox.state = config.nudgeModeAtStart ? .on : .off
        armedBox.state = config.armedSelectRed ? .on : .off
        for (name, popup) in buttonPopups {
            let action = config.action(for: name)
            popup.selectItem(at: ButtonAction.allCases.firstIndex(of: action) ?? 0)
        }
        for (name, popup) in shiftPopups {
            popup.selectItem(at: ButtonAction.allCases.firstIndex(of: config.shiftAction(for: name)) ?? 0)
        }
        notifyLostBox.state = Preferences.bool(Preferences.notifyDeskLost) ? .on : .off
        notifyBackBox.state = Preferences.bool(Preferences.notifyDeskBack) ? .on : .off
        notifySilentBox.state = Preferences.bool(Preferences.notifyLogicSilent) ? .on : .off
        for box in [notifyLostBox, notifyBackBox, notifySilentBox] where !Notifier.available {
            box.isEnabled = false
            box.toolTip = "Notifications only work from the app bundle"
        }
        connectSoundPopup.selectItem(withTitle: Preferences.string(Preferences.connectSound))
        lostSoundPopup.selectItem(withTitle: Preferences.string(Preferences.lostSound))
        hostField.stringValue = config.hostBundleID
    }

    @objc private func stepped(_ sender: NSStepper) {
        let field = sender == wakeStepper ? wakeField : valueField
        field.stringValue = String(format: "%.1f", sender.doubleValue)
        changed(sender)
    }

    @objc private func changed(_ sender: Any?) {
        guard !loading else { return }
        if let button = sender as? NSButton, button == loginBox {
            if #available(macOS 13, *) {
                do {
                    if loginBox.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
            onPreferenceChange?()
            return
        }
        Preferences.set(dockBox.state == .on, Preferences.hideDockIcon)
        Preferences.set(debugBox.state == .on, Preferences.debugLog)
        Preferences.set(notifyLostBox.state == .on, Preferences.notifyDeskLost)
        Preferences.set(notifyBackBox.state == .on, Preferences.notifyDeskBack)
        Preferences.set(notifySilentBox.state == .on, Preferences.notifyLogicSilent)
        onPreferenceChange?()

        var new = config
        new.deskWakeSeconds = min(max(Double(wakeField.stringValue) ?? config.deskWakeSeconds, 1), 30)
        new.valueDisplaySeconds = min(max(Double(valueField.stringValue) ?? config.valueDisplaySeconds, 0.2), 10)
        new.valuesInverse = inverseBox.state == .on
        new.nameStyle = namePopup.indexOfSelectedItem == 0 ? .proTools : .plain
        new.nameScroll = BridgeConfig.NameScroll.allCases[max(0, scrollPopup.indexOfSelectedItem)]
        new.timeDisplay = BridgeConfig.TimeDisplay.allCases[max(0, timePopup.indexOfSelectedItem)]
        new.meterModeAtStart = meterBox.state == .on
        new.nudgeModeAtStart = nudgeBox.state == .on
        new.armedSelectRed = armedBox.state == .on
        for (name, popup) in buttonPopups {
            if let raw = popup.selectedItem?.representedObject as? String, let action = ButtonAction(rawValue: raw) {
                new.buttons[name] = action
            }
        }
        for (name, popup) in shiftPopups {
            if let raw = popup.selectedItem?.representedObject as? String, let action = ButtonAction(rawValue: raw) {
                new.shiftButtons[name] = action == .none ? nil : action
            }
        }
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        new.hostBundleID = host.isEmpty ? BridgeConfig.default.hostBundleID : host
        if new != config {
            config = new
            onConfigChange?(new)
        } else {
            load()   // puts a mistyped number back
        }
    }

    @objc private func soundChanged(_ sender: NSPopUpButton) {
        guard !loading else { return }
        let key = sender == connectSoundPopup ? Preferences.connectSound : Preferences.lostSound
        Preferences.set(sender.titleOfSelectedItem, key)
        Preferences.play(key)
    }

    @objc private func chooseHost(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the application the desk should work with (it must support Mackie Control)."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        hostField.stringValue = id
        changed(hostField)
    }

    @objc private func choosePicture(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.message = "Choose a straight-down photo of the desk."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try DeskPicture.install(url) } catch { NSAlert(error: error).runModal(); return }
        onPictureChange?()
    }

    @objc private func removePicture(_ sender: Any?) {
        DeskPicture.remove()
        onPictureChange?()
    }

    @objc private func showLayoutFile(_ sender: Any?) {
        if !FileManager.default.fileExists(atPath: DeskPicture.userLayout.path) { try? DeskLayout.guess.save(to: DeskPicture.userLayout) }
        NSWorkspace.shared.activateFileViewerSelecting([DeskPicture.userLayout])
    }

    @objc private func showConfigFile(_ sender: Any?) {
        if !FileManager.default.fileExists(atPath: ConfigFile.url.path) { try? ConfigFile.save(config) }
        NSWorkspace.shared.activateFileViewerSelecting([ConfigFile.url])
    }

    @objc private func resetDefaults(_ sender: Any?) {
        config = .default
        onConfigChange?(config)
    }
}
