# Avid 003 Family driver 11.1.5 — discovery notes

The driver package is named for the 003 but drives the whole 00x family. The hardware
used for this project is a Digi 002. Port names below were confirmed against it.

Source: `003_Family_11.1.5.dmg` (final Mac release, 2018). Unpacked with custom UDIF, xar and cpio scripts.

## What the installer puts on disk

| Path | Arch | Role |
|---|---|---|
| `/Library/Extensions/Avid00Family.kext` (v11.2.1) | x86_64 | FireWire + IOAudioFamily kext. Does audio, MIDI mux/demux, device control. |
| `.../Avid00Family.kext/Contents/PlugIns/HAL Plug-in.bundle` | x86_64, i386 | Core Audio HAL plug-in loaded via `IOAudioEngineCoreAudioPlugIn`. |
| `/Library/Audio/MIDI Drivers/Avid 003 Family.plugin` | x86_64, i386 | CoreMIDI driver. Publishes MIDI ports from the kext as CoreMIDI entities. |
| `/Library/PreferencePanes/Avid 003 Family.prefPane` | x86_64, i386 | Trampoline that launches the Panel app. |
| `/Applications/Avid 003 Family.app` (Panel) | i386 only | Control panel. Dead on Catalina and later. |
| `/Library/Application Support/Avid/{F4CDDB0D-...}/DeviceInterface.dylib` | i386 only | Panel's device access library. Dead on Catalina and later. |
| `/Library/Application Support/Avid/{F4CDDB0D-...}/LaunchdDaemon` + `/Library/LaunchAgents/com.avid.00family.helper.plist` | — | Helper daemon, KeepAlive. |
| `/Library/Application Support/Digidesign/DHS/003.xml` + `.str` | — | Pro Tools hardware setup descriptions. |

Only the kext, HAL plug-in and MIDI plugin matter on Sonoma. The control panel and its dylib are 32-bit and cannot run.

## Kext

- Bundle id `com.avid.driver.firewire.00family`. Depends on IOAudioFamily and IOFireWireFamily.
- Personality `com_digidesign_003AudioDevice`: `IOProviderClass = IOFireWireDevice`, `Vendor_ID = 41086` (0xA07E, Digidesign). Covers 002, 002 Rack, 003, 003 Rack (model strings present).
- User client class `com_digidesign_003UserClient`.
- Written by M-Audio (class prefix `m_audio_003_`, "M-Audio FireWire" error strings). Build path `/Volumes/Development/179169/AudioDrivers/00Family/OSX/00Family/KernelExtension/`.
- Not stripped. Full C++ symbol names are present.

### User client methods (from symbols)

`StartMIDI`, `StopMIDI`, `SendMIDI(MAMIDIPacket*)`, `ReceivedMIDIPacket` (kernel to user push), `ProToolsOpen`, `ProToolsErrorReport`, `DiceGetRequest`, `DiceSetRequest` (raw FireWire register read/write by address), `clientMemoryForType`, `registerNotificationPort`. Dispatch table is `com_digidesign_003UserClient::sMethods`.

### Device registers written (FireWire address 0xE000_0xxx, big-endian quadlets)

| Offset | Purpose | Values |
|---|---|---|
| 0x110 | Sample rate | 0 = 44.1k, 1 = 48k, 2 = 88.2k, 3 = 96k |
| 0x118 | Clock source | enum |
| 0x11C | Optical input mode | inverted bool |
| 0x120 | S/PDIF compatibility | bool × 3 |

These match the Linux `snd-firewire-digi00x` driver's register map, which can be used as the reference for the rest.

### MIDI ports

`com_digidesign_003AudioDevice::SetupAudioEngine` registers the MIDI layout:

```
names         = ["Port 1", "Port 2", "Port 3 (Control)"]
input counts  = [1, 0, 1]
output counts = [1, 1, 1]
```

Published to the IORegistry as `MAMIDIPortsInfo` = { `MAMIDIInputCountsKey`, `MAMIDIOutputCountsKey`, `MAMIDIPortNamesKey` }.

Port 1 = physical MIDI in and out 1. Port 2 = physical MIDI out 2. Port 3 (Control) = the control surface, with both a source and a destination.

MIDI is multiplexed into the isochronous audio stream ("compound MIDI", `ProcessCompoundMIDIInputForPacket`, `ProcessCompoundMIDIOutput`, `ScheduleMidiPacket`). The DCL programs demux it into per-port ring buffers.

## CoreMIDI plugin

- Factory `Create003FireWireMIDIDriver`. Matches `com_digidesign_003AudioDevice` in the IORegistry, opens the user client with `IOServiceOpen`, calls `IOConnectCallScalarMethod`, maps shared memory with `IOConnectMapMemory`, and polls for input on a CFRunLoop timer (`checkForMIDIInput`).
- `rebuildEndpointArray` creates one CoreMIDI entity per port from `MAMIDIPortsInfo`. There is no code that hides or filters any port.

## Conclusion

The control surface is already exposed to every application as the CoreMIDI source and destination named "Port 3 (Control)". The device is named after the model: "Avid 002" for the Digi 002 used here, "Avid 003" for a 003. No kernel work is needed. The project reduces to a user-space CoreMIDI application that:

1. Opens the "Port 3 (Control)" source and destination.
2. Decodes the surface protocol (to be captured).
3. Emits Mackie Control on a virtual port for Logic, and translates Logic's feedback back to the surface.

## Next step

On the Sonoma Mac with the driver installed and the 002 connected:

1. Confirm the "Avid 002" device shows three ports including "Port 3 (Control)". Done 2026-10-24, see below.
2. Run a MIDI monitor on that source. Move one fader, press one button, turn one encoder, touch a fader. Record the bytes for each.
3. Send test messages to the destination (start with standard MIDI pitch bend, note on, and a few SysEx probes) and watch what the desk does.

The captured bytes decide the shape of the decoder.

## Confirmed on the host (2026-10-24)

FireWire: one device, vendor "Digidesign" (Vendor_ID 41086), product "Digi 002", Model_ID 1.
The kext's `com_digidesign_003AudioDevice` is attached to it.

CoreMIDI, device "Avid 002" (manufacturer "Avid", online):

| Entity | Sources | Destinations | Endpoint display name |
|---|---|---|---|
| Port 1 | 1 | 1 | Avid 002 Port 1 |
| Port 2 | 0 | 1 | Avid 002 Port 2 |
| Port 3 (Control) | 1 | 1 | Avid 002 Port 3 (Control) |

This matches the layout registered in `SetupAudioEngine`. Whether the 002 surface protocol matches the 003's is unknown until captured.
