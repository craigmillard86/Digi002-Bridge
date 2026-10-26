import CoreAudio
import Foundation

/// The desk as a Core Audio device, held open with a silent stream.
///
/// Avid's driver carries MIDI to the desk inside the isochronous audio stream
/// (docs/003-driver-discovery.md). While no program runs the desk's audio engine the
/// driver's outgoing MIDI buffer never drains; its send routine then waits a second per
/// message and nothing reaches the desk, although the desk's own messages still arrive.
/// Pro Tools never sees this because it keeps the engine running all session. This does
/// the same while the bridge is connected: a silent output stream, which costs nothing
/// and does not stop Logic or anything else using the device at the same time.
final class DeskAudio {
    struct Failure: Error, CustomStringConvertible {
        let call: String
        let status: OSStatus
        var description: String { "\(call) failed with OSStatus \(status)" }
    }

    private var device: AudioObjectID = 0
    private var procID: AudioDeviceIOProcID?
    /// Whether the silent stream is running.
    private(set) var holding = false
    /// Changes in the device's state (engine started or stopped by anyone, sample rate,
    /// overloads, the stream stopping on its own), in words. Called on a private queue.
    var onEvent: ((String) -> Void)?
    private let listenerQueue = DispatchQueue(label: "desk audio")
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    /// How many times the stream has called for a buffer, to notice it going quiet.
    private var callbacks = 0
    private var callbacksSeen = 0
    private var stalled = false
    private static let watched: [(AudioObjectPropertySelector, String)] = [
        (kAudioDevicePropertyDeviceIsRunning, "running"),
        (kAudioDevicePropertyDeviceIsRunningSomewhere, "running somewhere"),
        (kAudioDevicePropertyDeviceIsAlive, "alive"),
        (kAudioDevicePropertyNominalSampleRate, "sample rate"),
        (kAudioDeviceProcessorOverload, "overload"),
        (kAudioDevicePropertyIOStoppedAbnormally, "IO stopped abnormally"),
    ]

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func name(of device: AudioObjectID) -> String {
        var address = address(kAudioObjectPropertyName)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
        return status == noErr ? (value as String? ?? "") : ""
    }

    private static func flag(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    /// The desk's audio device ("Avid 002", "Avid 003"), if the driver has published one.
    static func findDevice() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return nil }
        return devices.first { device in
            let name = name(of: device)
            return (name.contains("002") || name.contains("003")) && flag(device, kAudioDevicePropertyDeviceIsAlive)
        }
    }

    /// Whether any program, this one included, is running the desk's audio engine.
    static func isRunning(_ device: AudioObjectID) -> Bool {
        flag(device, kAudioDevicePropertyDeviceIsRunningSomewhere)
    }

    /// Starts the silent stream. Does nothing if it is already running.
    func start() throws {
        guard !holding else { return }
        guard let found = Self.findDevice() else { throw Failure(call: "find desk audio device", status: 0) }
        device = found
        var proc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcID(device, { _, _, _, _, outData, _, clientData in
            for buffer in UnsafeMutableAudioBufferListPointer(outData) {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            if let clientData {
                let audio = Unmanaged<DeskAudio>.fromOpaque(clientData).takeUnretainedValue()
                audio.callbacks &+= 1
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque(), &proc)
        guard created == noErr, let proc else { throw Failure(call: "AudioDeviceCreateIOProcID", status: created) }
        let started = AudioDeviceStart(device, proc)
        guard started == noErr else {
            AudioDeviceDestroyIOProcID(device, proc)
            throw Failure(call: "AudioDeviceStart", status: started)
        }
        procID = proc
        holding = true
        callbacks = 0
        callbacksSeen = 0
        stalled = false
        watch()
    }

    /// Reports the device's state changes through `onEvent` while the stream is held.
    private func watch() {
        for (selector, label) in Self.watched {
            var address = Self.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                let value: String
                switch selector {
                case kAudioDevicePropertyNominalSampleRate:
                    var rate = 0.0
                    var size = UInt32(MemoryLayout<Double>.size)
                    var address = Self.address(selector)
                    value = AudioObjectGetPropertyData(self.device, &address, 0, nil, &size, &rate) == noErr ? "\(Int(rate))" : "?"
                case kAudioDeviceProcessorOverload, kAudioDevicePropertyIOStoppedAbnormally:
                    value = ""
                default:
                    value = Self.flag(self.device, selector) ? "yes" : "no"
                }
                self.onEvent?(value.isEmpty ? label : "\(label): \(value)")
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, listenerQueue, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    private func unwatch() {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, listenerQueue, block)
        }
        listeners = []
    }

    /// Called every few seconds while holding: says, once, when the stream stops asking
    /// for buffers, and when it starts again. The driver carries MIDI in that stream, so
    /// a silent stream means nothing reaches the desk whatever Core Audio reports.
    func checkStream() -> String? {
        guard holding else { return nil }
        let now = callbacks
        defer { callbacksSeen = now }
        if now == callbacksSeen, !stalled {
            stalled = true
            return "the desk's audio stream has stopped calling for buffers (engine running somewhere: \(Self.isRunning(device) ? "yes" : "no"))"
        }
        if now != callbacksSeen, stalled {
            stalled = false
            return "the desk's audio stream is calling for buffers again"
        }
        return nil
    }

    /// Stops the silent stream. Safe when it is not running or the device has gone.
    func stop() {
        guard holding, let proc = procID else { return }
        unwatch()
        AudioDeviceStop(device, proc)
        AudioDeviceDestroyIOProcID(device, proc)
        procID = nil
        holding = false
    }

    deinit { stop() }
}
