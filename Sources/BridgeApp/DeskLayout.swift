import AppKit
import Foundation

/// Where each control sits on the desk picture, in fractions of the picture's width and
/// height (0 to 1, from the top left), so one layout fits any size of the same photo.
/// Read from desk-layout.json next to desk.png (see `DeskPicture`).
struct DeskLayout: Codable {
    struct Strips: Codable {
        /// Left edge of each of the eight strips' display.
        var x: [Double]
        var displayY: Double, displayW: Double, displayH: Double
        var ringX: Double, ringY: Double, ringR: Double   // ringX: offset from x
        var ledX: Double, selY: Double, soloY: Double, muteY: Double, recY: Double, ledR: Double
        var faderX: Double, faderTop: Double, faderBottom: Double, capW: Double, capH: Double
    }

    var strips: Strips
    /// Displays 9 and 10: top-left corner of each; they share the strip display size.
    var display9: [Double]
    var display10: [Double]
    /// LED centre for each named button, by its name on the desk (Button.names).
    var leds: [String: [Double]]
    var ledR: Double

    /// A starting layout for a straight-down photo of a 002, to be corrected by hand.
    static let guess: DeskLayout = {
        let x = (0..<8).map { 0.075 + Double($0) * 0.0715 }
        return DeskLayout(
            strips: Strips(x: x, displayY: 0.33, displayW: 0.055, displayH: 0.03,
                           ringX: 0.028, ringY: 0.41, ringR: 0.022,
                           ledX: 0.008, selY: 0.47, soloY: 0.52, muteY: 0.57, recY: 0.445, ledR: 0.006,
                           faderX: 0.045, faderTop: 0.63, faderBottom: 0.95, capW: 0.03, capH: 0.02),
            display9: [0.70, 0.33], display10: [0.77, 0.33],
            leds: [:], ledR: 0.006)
    }()

    static func load(from url: URL) -> DeskLayout? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DeskLayout.self, from: data)
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// The desk photo and its layout: the user's own in Application Support first, then
/// one bundled with the app, else none (the view draws a schematic instead).
enum DeskPicture {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/002 Bridge")
    static let userImage = directory.appendingPathComponent("desk.png")
    static let userLayout = directory.appendingPathComponent("desk-layout.json")

    static func load() -> (NSImage, DeskLayout)? {
        let candidates: [(URL, URL)] = [
            (userImage, userLayout),
            (Bundle.main.resourceURL?.appendingPathComponent("desk.png") ?? userImage,
             Bundle.main.resourceURL?.appendingPathComponent("desk-layout.json") ?? userLayout),
        ]
        for (imageURL, layoutURL) in candidates {
            guard let image = NSImage(contentsOf: imageURL) else { continue }
            if let layout = DeskLayout.load(from: layoutURL) { return (image, layout) }
            // A picture without a layout gets the guess written next to it, to be edited.
            try? DeskLayout.guess.save(to: userLayout)
            return (image, DeskLayout.guess)
        }
        return nil
    }

    /// Copies a chosen picture in as desk.png (converted if it is not PNG).
    static func install(_ url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try png.write(to: userImage, options: .atomic)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: userImage)
    }
}
