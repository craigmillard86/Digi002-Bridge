# Project: Digi 002 (00x family) control surface to Logic Pro bridge

## Goal
Build a macOS user-space app that lets a Digidesign Digi 002 control surface
work with Logic Pro by translating its control protocol to Mackie Control (MCU).
Faders, encoders, buttons, transport, jog wheel and scribble strip, in both directions
(surface to Logic, and Logic feedback back to the motorised faders and display).

The unit on the bench is a Digi 002. Avid's driver treats the 002, 002 Rack, 003 and
003 Rack as one family, which is why the repo and some file names still say 003.
Build and test against the 002. 003 support is a possible later extension, not a goal.

## Target machine
Intel Mac running macOS 14 Sonoma with a Texas Instruments FireWire PCIe card.
Avid's final 003 Family driver (11.1.5, which also drives the 002) is installed via the Neyrinck helper utility.
The app only ever needs to run on Intel macOS 11 to 15. Tahoe removes FireWire,
and there is no Apple Silicon driver, so do not design for either.

## What is already known (see docs/003-driver-discovery.md for detail)
- Avid's kext exposes the desk's MIDI as three CoreMIDI ports. With the 002 connected,
  the device is named "Avid 002" (confirmed on this host, 2026-10-24); a 003 would show
  as "Avid 003". Ports:
  "Port 1" (physical MIDI in/out 1), "Port 2" (physical MIDI out 2), and
  "Port 3 (Control)" which is the control surface, with both a source and a destination.
- The CoreMIDI plugin publishes all three ports with no filtering, so any app can open
  Port 3 (Control). No kernel work, no IOKit user client, no private APIs are needed.
- The surface byte protocol on Port 3 is NOT yet decoded. Capture comes first.
  Do not assume the 002 and 003 surface protocols are the same.
- Find the control port by its name "Port 3 (Control)" on the Avid device, not by
  the device name, so the code is not tied to "Avid 002" or "Avid 003".
- The old Avid control panel is 32-bit and dead on modern macOS. Not our problem;
  sample rate and clock source still work through Audio MIDI Setup.
- Do not reverse engineer or borrow from Neyrinck's V-Control Pro. Avid's driver is
  the only third-party binary we study, and that is done. The extracted driver files
  are in reference/avid-driver-11.1.5/ for lookup only; nothing from them ships.

## Phase 1: capture tooling (do this first)
Write a small Swift command line tool (CoreMIDI, no third-party deps) that:
1. Lists all MIDI sources and destinations and confirms "Port 3 (Control)" exists.
2. Logs every incoming packet from Port 3 with a timestamp and hex bytes, with a
   label mode so I can type "fader1 up" and have it tag the following bytes.
3. Can send arbitrary hex to the Port 3 destination from the command line so I can
   probe the desk (pitch bend, note on, SysEx) and watch what the hardware does.
Output goes to a plain text log I can paste back for decoding.

Built as `Sources/capture` on the `MIDIIO` module. Usage:

    swift build
    .build/debug/capture list                  # ports, and whether the control port was found
    .build/debug/capture log                   # log to captures/<date>-<time>.log
    .build/debug/capture send B0 00 7F 20 70   # one message (waits 5 s for the desk to wake, holds 10 s)

While `log` runs, type a line to label the bytes that follow ("fader1 up"), type
`> 90 00 7F` to send bytes (logged as OUT), and `quit` or ctrl-D to stop.
Each log line is `<ms since start>  IN|OUT|LABEL  <hex bytes or label>`.

## Phase 2: protocol notes
From the 002 captures, write docs/protocol.md describing each control's message format,
in both directions. Keep it plain and tabular. This document is the main value of
the project and should outlive any particular code. State that it was
captured from a Digi 002 and that it is untested on a 003.

## Phase 3: bridge app
Swift, macOS 11+ deployment target, Intel. A menu bar app (or launch agent plus
small status UI) that:
- opens Port 3 (Control) source and destination,
- decodes surface messages into a clean internal model,
- creates a virtual MIDI source/destination pair named "003 MCU" and speaks
  Mackie Control to Logic on it,
- maps Logic's MCU feedback (fader positions, LEDs, LCD text, meters if available)
  back to the surface,
- has a config file for the few mappings worth changing.
First milestone: one fader moves one fader in Logic. Second: fader positions follow
Logic. Then fill in the rest of the MCU message set.

Status (2026-10-24): milestones 1 and 2 work with `.build/debug/bridge`, a command line
version. Modules: `Digi00x` (surface codec), `MCU` (Mackie Control codec), `BridgeCore`
(translation, no I/O), `bridge` (wires them to CoreMIDI). Mapped so far: faders 1-8 both
ways with touch, encoders as V-Pots with their rings following Logic, SEL/SOLO/MUTE and
the other buttons with LEDs, transport, and the displays showing Logic's track names and
values (4 characters each), Logic's meters on the rings (Meter button), flashing LEDs,
and the two right-hand displays showing the V-Pot assignment and the bar number. In
Logic, add a Mackie Control surface (Control Surfaces > Setup > New > Install) and set
both its ports to "003 MCU". The bridge connects to the desk only while Logic runs, so
the desk sleeps in standby when Logic is closed. `tools/install.sh [--login]` installs
the release build as `digi002-bridge`, with an optional launch agent. `docs/user-guide.md`
explains every button from the user's side. Not yet done: the display character set, a
config file.

## Phase 4: setup app

"002 Bridge.app" wraps the same bridge in a small window like Audio MIDI Setup: the desk,
Logic and bridge status, Start/Stop/Restart, Start at login (macOS 13+), setup help when
Logic is running but silent, and a log. A menu bar item shows the state and offers
Restart. The runtime lives in `BridgeRuntime` (`BridgeService`), shared with the command
line `bridge`. Build it with `tools/make-app.sh [--install]`; `tools/make-release.sh`
zips it with `docs/install.md` and the button guide for handing to someone else. It is
signed ad hoc unless `SIGN_IDENTITY` names a Developer ID certificate, so the first launch
needs right-click > Open (macOS 11–14) or Privacy & Security > Open Anyway (macOS 15). Planned next: the desk's audio settings (sample
rate, clock source, optical mode) to replace Avid's 32-bit control panel, if the driver
exposes them.

## Conventions
- Plain English in all docs and comments. No marketing tone.
- Keep the MIDI I/O layer, the 003 protocol layer and the MCU layer as separate
  modules with no cross-dependencies, so the protocol layer is reusable.
- Unit test the codecs with the captured byte sequences as fixtures.
  Use Swift Testing (`import Testing`), not XCTest. This machine has only the Command
  Line Tools (16.2, Swift 6.0.3), which do not include XCTest.
- Logic's MCU implementation is the reference for feedback; the Mackie Control
  protocol is publicly documented and there are open-source references to compare against.
