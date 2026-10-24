import CoreMIDI

/// A virtual MIDI source and destination pair that other apps (Logic) see as a device.
/// What we `send` appears on the source; what apps send to the destination reaches `receiver`.
public final class VirtualPort {
    private let connection: MIDIConnection
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private let receiver: MIDIConnection.Receiver

    /// `uniqueID`, when given, is set on both endpoints (the destination gets `uniqueID + 1`).
    /// Apps remember endpoints by unique ID, so a fixed one lets Logic pick the port up
    /// again at once after the bridge restarts instead of waiting for its next scan.
    public init(name: String, uniqueID: Int32? = nil, on connection: MIDIConnection,
                receiver: @escaping MIDIConnection.Receiver) throws {
        self.connection = connection
        self.receiver = receiver
        try connection.check("MIDISourceCreate", MIDISourceCreate(connection.client, name as CFString, &source))
        try connection.check("MIDIDestinationCreateWithBlock",
                             MIDIDestinationCreateWithBlock(connection.client, name as CFString, &destination) {
                                 [weak self] list, _ in
                                 guard let self else { return }
                                 MIDIConnection.forEachPacket(list, self.receiver)
                             })
        if let uniqueID {
            // A clash with another endpoint is not fatal; CoreMIDI then keeps the one it chose.
            MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, uniqueID)
            MIDIObjectSetIntegerProperty(destination, kMIDIPropertyUniqueID, uniqueID + 1)
        }
    }

    deinit {
        MIDIEndpointDispose(source)
        MIDIEndpointDispose(destination)
    }

    /// Makes `bytes` appear on the virtual source, timestamped now.
    public func send(_ bytes: [UInt8]) throws {
        try MIDIConnection.withPacketList(bytes) { list in
            try connection.check("MIDIReceived", MIDIReceived(source, list))
        }
    }
}
