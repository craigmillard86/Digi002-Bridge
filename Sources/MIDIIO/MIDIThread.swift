import CoreMIDI
import Foundation

/// The thread every CoreMIDI client is created on.
///
/// CoreMIDI refreshes a process's picture of the ports, and delivers setup-change
/// notifications, through the run loop of the thread that created the client. A client
/// created on a dispatch queue, or in a program that ends in `dispatchMain()`, never
/// learns that a device has appeared or gone: `MIDIGetNumberOfSources` keeps returning
/// the list from the moment the client was made. Measured on macOS 14 with a virtual
/// source toggled from another process. So clients are made here, on a thread that does
/// nothing but run its loop, and the rest of the program can live on any queue.
///
/// The same goes for the very first CoreMIDI call of any kind: CoreMIDI sets up the
/// process's connection to the server, and the port list that goes with it, on the thread
/// that makes it. So the thread primes CoreMIDI before anything else can, and the port
/// listings in `Endpoints` run here too (seen in the app: a listing made on a dispatch
/// queue before any client existed left the app blind to the desk being switched on).
final class MIDIThread {
    static let shared = MIDIThread()

    private let runLoop: CFRunLoop

    private final class Box<T> { var value: T? }

    private init() {
        let box = Box<CFRunLoop>()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.value = CFRunLoopGetCurrent()
            // A port keeps the loop alive with nothing else scheduled on it.
            RunLoop.current.add(Port(), forMode: .default)
            // The first CoreMIDI call in the process, so its setup belongs to this thread.
            _ = MIDIGetNumberOfDevices()
            ready.signal()
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = "CoreMIDI client"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
        runLoop = box.value!
    }

    /// Runs `body` on the MIDI thread and waits for it. Safe to call from the thread itself.
    func sync<T>(_ body: @escaping () throws -> T) throws -> T {
        if CFRunLoopGetCurrent() == runLoop { return try body() }
        let slot = Box<Result<T, Error>>()
        let done = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            slot.value = Result { try body() }
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        done.wait()
        return try slot.value!.get()
    }
}
