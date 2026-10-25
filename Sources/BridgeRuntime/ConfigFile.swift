import BridgeCore
import Foundation

/// Where the bridge's settings live on disk, shared by the app and the command line tool:
/// ~/Library/Application Support/002 Bridge/config.json. A missing file means defaults;
/// a file that cannot be parsed is reported and ignored rather than stopping the bridge.
public enum ConfigFile {
    public static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/002 Bridge")
    public static let url = directory.appendingPathComponent("config.json")

    public enum Outcome {
        case defaults            // no file
        case loaded(BridgeConfig)
        case invalid(String)     // file exists but could not be read; defaults are used
    }

    public static func load(from url: URL = url) -> Outcome {
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        do {
            return .loaded(try BridgeConfig.from(json: Data(contentsOf: url)))
        } catch {
            return .invalid("\(url.path): \(error.localizedDescription)")
        }
    }

    /// The config to run with, whatever the file's state.
    public static func config(from outcome: Outcome) -> BridgeConfig {
        if case let .loaded(config) = outcome { return config }
        return .default
    }

    public static func save(_ config: BridgeConfig, to url: URL = url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.json().write(to: url, options: .atomic)
    }
}
