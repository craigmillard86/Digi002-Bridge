// Probes the desk as a Core Audio device: is its audio engine running (streaming to
// some app), and does running it wake the desk from standby?
// Usage: swift tools/audio-probe.swift            lists devices and whether each is running
//        swift tools/audio-probe.swift --run 30   runs a silent IOProc on the 002/003 for 30 s
import CoreAudio
import Foundation

func property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var address = property(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString? = nil
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
    return status == noErr ? (value as String? ?? "") : ""
}

func uint(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
    var address = property(selector)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    return value
}

var address = property(kAudioHardwarePropertyDevices)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)

var desk: AudioObjectID?
for device in devices {
    let name = string(device, kAudioObjectPropertyName)
    let running = uint(device, kAudioDevicePropertyDeviceIsRunningSomewhere) != 0
    let alive = uint(device, kAudioDevicePropertyDeviceIsAlive) != 0
    print("\(device)\t\(name)\trunning: \(running)\talive: \(alive)")
    if name.contains("002") || name.contains("003") { desk = device }
}

let args = CommandLine.arguments
if let index = args.firstIndex(of: "--run"), let desk {
    let seconds = args.count > index + 1 ? Double(args[index + 1]) ?? 30 : 30
    var procID: AudioDeviceIOProcID?
    let status = AudioDeviceCreateIOProcID(desk, { _, _, _, _, outData, _, _ in
        // Silence: zero every output buffer.
        let buffers = UnsafeMutableAudioBufferListPointer(outData)
        for buffer in buffers { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
        return noErr
    }, nil, &procID)
    guard status == noErr, let procID else { print("could not create IOProc: \(status)"); exit(1) }
    let start = AudioDeviceStart(desk, procID)
    print("started silent audio on the desk (status \(start)); running for \(seconds) s")
    Thread.sleep(forTimeInterval: seconds)
    AudioDeviceStop(desk, procID)
    AudioDeviceDestroyIOProcID(desk, procID)
    print("stopped")
}
