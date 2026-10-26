import Digi00x
import Foundation

/// Notices a desk that has stopped taking commands, from how its faders behave.
///
/// The desk's motors hold each fader at the last position the host gave it. A desk that
/// is taking commands is told where a fader was left the moment it is released (the
/// bridge echoes the position, then Logic sends its own), so after a release the fader
/// stays put, or moves to wherever the bridge has since sent it. A desk that has stopped
/// taking commands never hears the new position: on release the motor drags the fader
/// back to the old one, and the desk reports that movement as it would a hand.
///
/// So a snap-back is: within a moment of a release, with no hand on it, the fader reports
/// a position well away from where it was left, and further from the last position the
/// bridge sent than the release was. The desk sometimes reports a position a millisecond
/// before the touch that caused it, so a verdict waits `graceSeconds` for a touch to
/// explain the move. One snap-back can still be a fluke; the caller counts them.
public struct StuckDetector {
    public struct SnapBack: Equatable {
        public let channel: Int
        /// Where the fader was left.
        public let released: Int
        /// Where the desk then reported it, untouched.
        public let reported: Int
    }

    /// How long after a release an untouched move counts.
    public static let windowSeconds = 2.0
    /// How long a move must stand without a touch before it is a snap-back.
    public static let graceSeconds = 0.15
    /// Smallest move that counts, in fader units (0 to 1023); a jitter is far smaller.
    public static let minimumJump = 80

    private var touched = Set<Int>()
    private var lastReported: [Int: Int] = [:]
    private var released: [Int: (at: Date, position: Int)] = [:]
    private var sent: [Int: Int] = [:]
    private var pending: [Int: (at: Date, snapBack: SnapBack)] = [:]

    public init() {}

    /// Every event from the desk.
    public mutating func surface(_ event: SurfaceEvent, at now: Date) {
        switch event {
        case let .faderTouch(channel, isTouched):
            if isTouched {
                touched.insert(channel)
                pending[channel] = nil      // a hand explains the move
                released[channel] = nil
            } else {
                touched.remove(channel)
                if let position = lastReported[channel] {
                    released[channel] = (now, position)
                }
            }
        case let .fader(channel, position):
            lastReported[channel] = position
            guard !touched.contains(channel), pending[channel] == nil,
                  let release = released[channel],
                  now.timeIntervalSince(release.at) <= Self.windowSeconds else { return }
            guard abs(position - release.position) >= Self.minimumJump else { return }
            // Moving towards where the bridge sent it is the motor doing as it was told.
            if let target = sent[channel], abs(position - target) <= abs(release.position - target) { return }
            pending[channel] = (now, SnapBack(channel: channel, released: release.position, reported: position))
        default:
            break
        }
    }

    /// Every command the bridge sends the desk, so a move it asked for is not a snap-back.
    public mutating func sent(_ command: SurfaceCommand) {
        if case let .fader(channel, position) = command { sent[channel] = position }
    }

    /// Snap-backs that have stood for `graceSeconds` with no touch to explain them.
    /// Call regularly; each release yields at most one.
    public mutating func confirmed(at now: Date) -> [SnapBack] {
        var out: [SnapBack] = []
        for (channel, item) in pending where now.timeIntervalSince(item.at) >= Self.graceSeconds {
            out.append(item.snapBack)
            pending[channel] = nil
            released[channel] = nil
        }
        return out.sorted { $0.channel < $1.channel }
    }
}
