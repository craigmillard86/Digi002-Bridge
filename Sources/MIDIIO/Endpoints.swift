import CoreMIDI

/// A CoreMIDI source or destination, with the names needed to pick it out.
public struct Endpoint {
    public enum Direction: String {
        case source, destination
    }

    public let ref: MIDIEndpointRef
    public let direction: Direction
    /// The name CoreMIDI shows to users, e.g. "Avid 002 Port 3 (Control)".
    public let displayName: String
    /// The entity (port) name, e.g. "Port 3 (Control)". Empty for virtual endpoints.
    public let entityName: String
    /// The device name, e.g. "Avid 002". Empty for virtual endpoints.
    public let deviceName: String
    public let manufacturer: String
    public let isOffline: Bool
}

public enum Endpoints {
    /// The entity name Avid's driver gives the control surface port on every 00x unit.
    public static let controlPortName = "Port 3 (Control)"

    public static func sources() -> [Endpoint] {
        (0..<MIDIGetNumberOfSources()).map { describe(MIDIGetSource($0), .source) }
    }

    public static func destinations() -> [Endpoint] {
        (0..<MIDIGetNumberOfDestinations()).map { describe(MIDIGetDestination($0), .destination) }
    }

    /// Finds the control surface port by its port name on an Avid/Digidesign device,
    /// so it works whether the device shows up as "Avid 002" or "Avid 003".
    public static func controlPort(_ direction: Endpoint.Direction) -> Endpoint? {
        all(direction).first { ep in
            ep.entityName == controlPortName && isAvidDevice(ep)
        }
    }

    /// Finds the first endpoint whose display name contains `text`, ignoring case.
    public static func matching(_ text: String, _ direction: Endpoint.Direction) -> Endpoint? {
        all(direction).first { $0.displayName.localizedCaseInsensitiveContains(text) }
    }

    private static func all(_ direction: Endpoint.Direction) -> [Endpoint] {
        direction == .source ? sources() : destinations()
    }

    private static func isAvidDevice(_ ep: Endpoint) -> Bool {
        ep.manufacturer == "Avid" || ep.manufacturer == "Digidesign"
            || ep.deviceName.hasPrefix("Avid") || ep.deviceName.hasPrefix("Digi")
    }

    private static func describe(_ ref: MIDIEndpointRef, _ direction: Endpoint.Direction) -> Endpoint {
        var entity = MIDIEntityRef()
        var device = MIDIDeviceRef()
        let hasEntity = MIDIEndpointGetEntity(ref, &entity) == noErr && entity != 0
        let hasDevice = hasEntity && MIDIEntityGetDevice(entity, &device) == noErr && device != 0
        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(ref, kMIDIPropertyOffline, &offline)
        return Endpoint(
            ref: ref,
            direction: direction,
            displayName: string(ref, kMIDIPropertyDisplayName),
            entityName: hasEntity ? string(entity, kMIDIPropertyName) : "",
            deviceName: hasDevice ? string(device, kMIDIPropertyName) : "",
            manufacturer: hasDevice ? string(device, kMIDIPropertyManufacturer) : "",
            isOffline: offline != 0
        )
    }

    static func string(_ object: MIDIObjectRef, _ key: CFString) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, key, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }
}
