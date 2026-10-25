import AppKit

// "002 Bridge": a small setup app around BridgeService, in the spirit of Audio MIDI Setup.
// Built as a bundle by tools/make-app.sh. Everything is laid out in code; no storyboard.

// One copy only. Finder refuses to open the same bundle twice, but a copy at another
// path (build/ next to /Applications) would start, hold the desk and confuse Logic, so
// it hands over to the running one instead.
if let id = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if let other = others.first {
        other.activate(options: [.activateIgnoringOtherApps])
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
