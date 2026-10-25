import AppKit
import Foundation

/// App-only settings (the bridge's own are in the config file, see ConfigFile). Kept in
/// UserDefaults under the keys below.
enum Preferences {
    static let debugLog = "debugLog"
    static let hideDockIcon = "hideDockIcon"
    static let notifyDeskLost = "notifyDeskLost"
    static let notifyDeskBack = "notifyDeskBack"
    static let notifyLogicSilent = "notifyLogicSilent"
    static let connectSound = "connectSound"
    static let lostSound = "lostSound"

    static let defaults: [String: Any] = [
        debugLog: true,
        hideDockIcon: false,
        notifyDeskLost: true,
        notifyDeskBack: false,
        notifyLogicSilent: true,
        connectSound: "None",
        lostSound: "None",
    ]

    /// The system alert sounds, by name, as NSSound finds them.
    static let sounds = ["None", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
                         "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    static func register() { UserDefaults.standard.register(defaults: defaults) }
    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func string(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? "" }
    static func set(_ value: Any?, _ key: String) { UserDefaults.standard.set(value, forKey: key) }

    static func play(_ key: String) {
        let name = string(key)
        guard name != "None", let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.play()
    }
}
