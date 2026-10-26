import Testing
import Digi00x
import Foundation
@testable import BridgeCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1000)
private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

/// A hand moves fader `channel` from `from` to `to` and lets go; the bridge echoes `to`.
private func drag(_ detector: inout StuckDetector, channel: Int = 2, from: Int, to: Int, at start: Double) -> Double {
    detector.surface(.faderTouch(channel: channel, touched: true), at: at(start))
    detector.surface(.fader(channel: channel, position: from), at: at(start + 0.01))
    detector.surface(.fader(channel: channel, position: to), at: at(start + 0.20))
    detector.surface(.faderTouch(channel: channel, touched: false), at: at(start + 0.25))
    detector.sent(.fader(channel: channel, position: to))
    return start + 0.25
}

@Test func aFaderThatStaysWhereItWasLeftIsFine() {
    var detector = StuckDetector()
    let released = drag(&detector, from: 700, to: 400, at: 0)
    #expect(detector.confirmed(at: at(released + 1)) == [])
}

@Test func aFaderDraggedBackByTheMotorAfterReleaseIsASnapBack() {
    var detector = StuckDetector()
    let released = drag(&detector, from: 700, to: 400, at: 0)
    // The old target was 700; the desk never took 400 and the motor goes back.
    detector.surface(.fader(channel: 2, position: 560), at: at(released + 0.3))
    detector.surface(.fader(channel: 2, position: 690), at: at(released + 0.4))
    #expect(detector.confirmed(at: at(released + 0.35)) == [])     // still inside the grace period
    #expect(detector.confirmed(at: at(released + 0.6)) == [StuckDetector.SnapBack(channel: 2, released: 400, reported: 560)])
    #expect(detector.confirmed(at: at(released + 1.0)) == [])     // one verdict per release
}

@Test func aPositionReportedJustBeforeTheTouchThatMovedItIsNotASnapBack() {
    var detector = StuckDetector()
    let released = drag(&detector, from: 700, to: 400, at: 0)
    // Seen on the desk: the position byte lands a millisecond before the touch.
    detector.surface(.fader(channel: 2, position: 552), at: at(released + 0.7))
    detector.surface(.faderTouch(channel: 2, touched: true), at: at(released + 0.701))
    #expect(detector.confirmed(at: at(released + 1.0)) == [])
}

@Test func aMoveTowardsWhereTheBridgeSentTheFaderIsTheMotorObeying() {
    var detector = StuckDetector()
    let released = drag(&detector, from: 700, to: 400, at: 0)
    // Logic's own value (automation, say) sends the fader on up; it reports on the way.
    detector.sent(.fader(channel: 2, position: 800))
    detector.surface(.fader(channel: 2, position: 600), at: at(released + 0.3))
    #expect(detector.confirmed(at: at(released + 1.0)) == [])
}

@Test func smallMovesAndLateMovesDoNotCount() {
    var detector = StuckDetector()
    let released = drag(&detector, from: 700, to: 400, at: 0)
    detector.surface(.fader(channel: 2, position: 430), at: at(released + 0.3))     // jitter
    detector.surface(.fader(channel: 2, position: 700), at: at(released + 3.0))     // too late to be the release
    #expect(detector.confirmed(at: at(released + 4.0)) == [])
}

@Test func channelsAreIndependent() {
    var detector = StuckDetector()
    let released = drag(&detector, channel: 0, from: 100, to: 900, at: 0)
    _ = drag(&detector, channel: 1, from: 500, to: 500, at: 0.5)
    detector.surface(.fader(channel: 0, position: 150), at: at(released + 0.3))
    let snaps = detector.confirmed(at: at(released + 1.0))
    #expect(snaps.map(\.channel) == [0])
}
