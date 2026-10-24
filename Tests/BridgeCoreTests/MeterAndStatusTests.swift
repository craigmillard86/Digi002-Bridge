import Testing
import Digi00x
import MCU
@testable import BridgeCore

private func leds(_ ring: Ring) -> [Int] { (1...14).filter { ring.leds & (1 << ($0 - 1)) != 0 } }
private let meter = Button.named("Meter")!

@Test func meterRingIsBarPlusPeakDotPlusRedClip() {
    #expect(leds(Bridge.meterRing(level: 0, peak: 0, clip: false)) == [])
    #expect(leds(Bridge.meterRing(level: 6, peak: 6, clip: false)) == Array(1...7))
    #expect(leds(Bridge.meterRing(level: 12, peak: 12, clip: false)) == Array(1...14))
    #expect(leds(Bridge.meterRing(level: 3, peak: 9, clip: false)) == [1, 2, 3, 4, 11])
    #expect(Bridge.meterRing(level: 0, peak: 0, clip: true).lastRed)
}

@Test func meterButtonSwitchesRingsBetweenVPotsAndMeters() {
    var bridge = Bridge()
    _ = bridge.fromLogic(.vpotRing(channel: 0, centre: false, mode: .wrap, position: 3))
    // Meters arrive all the time but do not touch the rings until meter mode is on.
    #expect(bridge.fromLogic(.meter(channel: 0, level: 9)).toSurface == [])

    let on = bridge.fromSurface(.button(meter, pressed: true))
    #expect(bridge.meterMode)
    #expect(on.toLogic == [])
    #expect(on.toSurface.first == .led(meter, on: true))
    #expect(on.toSurface.contains(.ring(channel: 0, Bridge.meterRing(level: 9, peak: 9, clip: false))))
    _ = bridge.fromSurface(.button(meter, pressed: false))

    let off = bridge.fromSurface(.button(meter, pressed: true))
    #expect(!bridge.meterMode)
    #expect(off.toSurface.contains(.ring(channel: 0, Bridge.ring(centre: false, mode: .wrap, position: 3))))
}

@Test func peakHoldsThenFallsAndClipTimesOut() {
    var bridge = Bridge()
    _ = bridge.fromSurface(.button(meter, pressed: true))
    _ = bridge.fromLogic(.meter(channel: 2, level: 10))
    _ = bridge.fromLogic(.meter(channel: 2, level: 2))
    _ = bridge.fromLogic(.meter(channel: 2, level: 0xE))
    for _ in 0..<(Bridge.peakHoldTicks - 1) { #expect(bridge.tick() == []) }
    // The peak starts to fall one level per tick.
    #expect(bridge.tick() == [.ring(channel: 2, Bridge.meterRing(level: 2, peak: 9, clip: true))])
    for _ in 0..<(Bridge.clipHoldTicks - Bridge.peakHoldTicks - 1) { _ = bridge.tick() }
    #expect(bridge.tick() == [.ring(channel: 2, Bridge.meterRing(level: 2, peak: 2, clip: false))])
    // Logic can clear the clip itself.
    _ = bridge.fromLogic(.meter(channel: 2, level: 0xE))
    #expect(bridge.fromLogic(.meter(channel: 2, level: 0xF)).toSurface == [.ring(channel: 2, Bridge.meterRing(level: 2, peak: 2, clip: false))])
}

@Test func flashingLEDsToggleOnTheTimer() {
    var bridge = Bridge()
    #expect(bridge.fromLogic(.ledFlash(.recArm(1))).toSurface == [.led(.recordReady(1), on: true)])
    for _ in 0..<(Bridge.flashHalfPeriodTicks - 1) { #expect(bridge.tick() == []) }
    #expect(bridge.tick() == [.led(.recordReady(1), on: false)])
    for _ in 0..<(Bridge.flashHalfPeriodTicks - 1) { _ = bridge.tick() }
    #expect(bridge.tick() == [.led(.recordReady(1), on: true)])
    // A steady state from Logic stops the flashing.
    _ = bridge.fromLogic(.note(.recArm(1), on: false))
    for _ in 0..<Bridge.flashHalfPeriodTicks { #expect(bridge.tick() == []) }
}

@Test func rightHandDisplaysShowAssignmentAndPosition() {
    var bridge = Bridge()
    let pan = bridge.fromLogic(.note(.assignPan, on: true))
    #expect(pan.toSurface.contains(.display(strip: 8, text: "Pan", inverse: false)))
    #expect(bridge.fromLogic(.note(.assignSend, on: true)).toSurface.contains(.display(strip: 8, text: "Send", inverse: false)))
    // Bars/beats "  5 1 1 0": the bar number is in positions 9-7.
    _ = bridge.fromLogic(.sevenSegment(position: 9, character: " ", dot: false))
    _ = bridge.fromLogic(.sevenSegment(position: 8, character: " ", dot: false))
    let out = bridge.fromLogic(.sevenSegment(position: 7, character: "5", dot: false))
    #expect(out.toSurface == [.display(strip: 9, text: "  5 ", inverse: false)])
    // An unchanged character sends nothing.
    #expect(bridge.fromLogic(.sevenSegment(position: 6, character: " ", dot: true)).toSurface == [])
    #expect(bridge.startup().contains(.display(strip: 9, text: "  5 ", inverse: false)))
    #expect(bridge.startup().contains(.led(meter, on: false)))
}

@Test func rtzIsStopPressedTwice() {
    var bridge = Bridge()
    let press = bridge.fromSurface(.button(Button.named("RTZ")!, pressed: true))
    #expect(press.toLogic == [.note(.stop, on: true), .note(.stop, on: false), .note(.stop, on: true)])
    #expect(bridge.fromSurface(.button(Button.named("RTZ")!, pressed: false)).toLogic == [.note(.stop, on: false)])
}
