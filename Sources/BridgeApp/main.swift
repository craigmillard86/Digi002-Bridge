import AppKit

// "002 Bridge": a small setup app around BridgeService, in the spirit of Audio MIDI Setup.
// Built as a bundle by tools/make-app.sh. Everything is laid out in code; no storyboard.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
