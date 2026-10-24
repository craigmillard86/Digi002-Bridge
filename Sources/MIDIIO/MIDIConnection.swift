import CoreMIDI

public struct MIDIError: Error, CustomStringConvertible {
    public let call: String
    public let status: OSStatus

    public var description: String { "\(call) failed with OSStatus \(status)" }
}

/// A CoreMIDI client with one input port and one output port.
///
/// Uses the MIDIPacketList API rather than the newer Universal MIDI Packet one, because
/// it passes the driver's bytes through unchanged. That matters while the surface
/// protocol is unknown: nothing gets reinterpreted or dropped on the way in.
public final class MIDIConnection {
    /// Called on a CoreMIDI thread for each packet. `hostTime` is in mach_absolute_time units.
    public typealias Receiver = (_ hostTime: UInt64, _ bytes: [UInt8]) -> Void

    private(set) var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var receiver: Receiver?

    public init(name: String) throws {
        try check("MIDIClientCreateWithBlock",
                  MIDIClientCreateWithBlock(name as CFString, &client, nil))
        try check("MIDIOutputPortCreate",
                  MIDIOutputPortCreate(client, "\(name) out" as CFString, &outputPort))
        try check("MIDIInputPortCreateWithBlock",
                  MIDIInputPortCreateWithBlock(client, "\(name) in" as CFString, &inputPort) {
                      [weak self] list, _ in self?.deliver(list)
                  })
    }

    deinit {
        MIDIClientDispose(client)
    }

    /// Starts delivering packets from `source` to `receiver`. Only one receiver is kept.
    public func listen(to source: Endpoint, receiver: @escaping Receiver) throws {
        self.receiver = receiver
        try check("MIDIPortConnectSource", MIDIPortConnectSource(inputPort, source.ref, nil))
    }

    /// Stops listening to `source`. For the desk this is what "disconnecting" means: with no
    /// client on its control port it goes back to standby.
    public func stopListening(to source: Endpoint) throws {
        try check("MIDIPortDisconnectSource", MIDIPortDisconnectSource(inputPort, source.ref))
    }

    /// Sends `bytes` as one packet, timestamped now. SysEx up to a few KB is fine.
    public func send(_ bytes: [UInt8], to destination: Endpoint) throws {
        try Self.withPacketList(bytes) { list in
            try check("MIDISend", MIDISend(outputPort, destination.ref, list))
        }
    }

    private func deliver(_ list: UnsafePointer<MIDIPacketList>) {
        guard let receiver else { return }
        Self.forEachPacket(list, receiver)
    }

    /// Builds a one-packet list holding `bytes`, timestamped now, for the duration of `body`.
    static func withPacketList(_ bytes: [UInt8], _ body: (UnsafePointer<MIDIPacketList>) throws -> Void) rethrows {
        let size = MemoryLayout<MIDIPacketList>.size + bytes.count + 64
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        let list = buffer.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(list)
        // The buffer is sized for this message, so MIDIPacketListAdd cannot run out of room.
        _ = MIDIPacketListAdd(list, size, packet, 0, bytes.count, bytes)
        try body(list)
    }

    static func forEachPacket(_ list: UnsafePointer<MIDIPacketList>, _ receiver: Receiver) {
        let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.length)
            let start = UnsafeRawPointer(packet).advanced(by: dataOffset)
            let bytes = Array(UnsafeRawBufferPointer(start: start, count: count))
            receiver(packet.pointee.timeStamp, bytes)
        }
    }

    func check(_ call: String, _ status: OSStatus) throws {
        if status != noErr { throw MIDIError(call: call, status: status) }
    }
}
