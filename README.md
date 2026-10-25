# 002 Bridge

002 Bridge lets a Digidesign Digi 002 control surface work with Logic Pro on an Intel
Mac. Pro Tools is not needed. The desk's faders, encoders, buttons and displays work
with Logic the way a Mackie Control does, in both directions: the desk drives Logic,
and Logic drives the desk's motorised faders, LEDs, encoder rings and displays.

## How it works

Avid's free 003 Family driver makes the desk appear on the Mac as a MIDI device. One of
its ports, "Port 3 (Control)", carries the control surface: every fader move and button
press comes out of it, and fader positions, LED states and display text go into it.
That port speaks the desk's own language, which only Pro Tools understood.

002 Bridge is a small app that sits on that port. It translates what the desk says into
Mackie Control, the control surface protocol Logic understands, and offers it to Logic
on a MIDI port named "003 MCU". Logic treats that port as a Mackie Control and sends its
feedback back the same way; the bridge turns it into the desk's language and the faders
move, the LEDs light and the names appear.

    Digi 002  <-- FireWire -->  Avid driver  <-- "Port 3 (Control)" -->  002 Bridge  <-- "003 MCU" -->  Logic Pro

The bridge connects to the desk only while Logic (or whichever host you choose) is
running, so the desk sleeps in standby the rest of the time. It runs in the background
from login with a menu bar item, and a window shows what is going on when you want it.

## What it does

- **Faders.** The eight motorised faders follow Logic's volume and automation. Touching
  a fader hands it to you until you let go.
- **Encoders.** The eight encoders are Logic's V-Pots: pan, sends, plug-in, EQ or
  instrument parameters, chosen with the desk's Pan, Send, Insert, EQ and Dynamics
  buttons. The LED rings follow Logic. Flip swaps encoders and faders.
- **Buttons and LEDs.** SEL, SOLO, MUTE, record arm (hold Rec and press SEL), the
  navigation pad, Bank/Nudge/Zoom, Undo, Enter, Esc, the four modifiers, F1–F5, the
  window keys and the transport, each with its LED lit from Logic's state. Loop Play
  is Cycle, Quick Punch is Autopunch, Loop Rec is Replace, RTZ returns to the start.
- **Displays.** The 4-character display above each strip shows the track name,
  shortened the way Pro Tools did it ("Audio 1" is "Aud1") or scrolling, and the value
  for a moment while you turn an encoder. The two right-hand displays show the encoder
  assignment and the song position, in a choice of layouts.
- **Meters.** The Meter button puts Logic's channel meters on the encoder rings, with
  peak hold and a clip LED, as Pro Tools used them.
- **Spare buttons.** A to E, Master Bypass and Master Faders have no Mackie Control
  meaning, so you choose what they do (markers, click, save, scrub, cycle, screensets,
  user switches, transport and more), with a second function each for while Shift is held.
- **Standby.** The desk wakes when Logic starts and goes back to standby when Logic quits,
  so it is not lit all day. Switching the desk off and on while the bridge runs is fine.
- **The app.** A window like Audio MIDI Setup shows the desk, Logic and bridge status, a
  drawing of the desk as the bridge last sent it (or your own photo with the live state
  drawn over it), and a log. A menu bar item shows the state as a coloured dot. Settings
  cover everything above, start at login, menu bar only, notifications and sounds.

The host does not have to be Logic: any program that speaks Mackie Control can be chosen
in Settings.

## Requirements

- An Intel Mac running macOS 11 Big Sur to macOS 15 Sequoia. macOS 26 drops FireWire
  and there is no Apple Silicon driver for the desk, so neither is supported.
- A Digi 002 connected by FireWire. The 002 Rack, 003 and 003 Rack use the same driver
  and probably the same protocol, but only the 002 has been tested.
- Avid's "003 Family" driver, version 11.1.5, the last one released. It is a free
  download from Avid.
- Logic Pro, or another Mackie Control host.

## Installing

The full version of these steps, with what to do when something does not work, is in
[docs/install.md](docs/install.md).

1. **Install Avid's driver** and restart. On a modern macOS the installer may say the
   system extension was blocked: allow it in System Settings > Privacy & Security and
   restart again. Check in Audio MIDI Setup (Window > Show MIDI Studio) that an
   "Avid 002" or "Avid 003" device appears with a "Port 3 (Control)" port.
2. **Install the app.** Either download the latest `002-Bridge-<version>.zip` from the
   [releases page](https://github.com/craigmillard86/Digi002-Bridge/releases) and drag
   "002 Bridge.app" into Applications, or build it from source (below). The app is not
   notarised, so the first launch needs right-click > Open on macOS 11 to 14, or System
   Settings > Privacy & Security > Open Anyway on macOS 15.
3. **Set up Logic, once.** Logic Pro > Control Surfaces > Setup, New > Install, choose
   Mackie Designs > Mackie Control, and set both its ports to "003 MCU". Then in
   Logic Pro > Settings > MIDI > Inputs tick "003 MCU" and untick "Avid 002 Port 3
   (Control)".
4. Open the app, and in its Settings tick "Start at login" so it is always there.

Within a few seconds of opening Logic the desk wakes, the faders move to Logic's
positions and the displays show the track names.

### Building it yourself

If there is no download, or you want the latest version, the app builds with Apple's
free Command Line Tools and nothing else:

```
xcode-select --install
git clone https://github.com/craigmillard86/Digi002-Bridge.git
cd Digi002-Bridge
tools/make-app.sh --install
```

That puts "002 Bridge.app" in Applications. If you would rather have no window at all,
`tools/install.sh --login` installs a background version that starts at login instead.

## Using it

Open Logic and the desk comes to life. [docs/user-guide.md](docs/user-guide.md) explains
every button from the user's side, and [docs/config.md](docs/config.md) the settings and
the config file (`~/Library/Application Support/002 Bridge/config.json`), which the app's
Settings window edits.

If the desk shows "Standby" with Logic open, or buttons do nothing while the displays
fill in, the checklist in [docs/install.md](docs/install.md#if-something-does-not-work)
covers the usual causes: the "003 MCU" input unticked in Logic, two copies of the bridge
running, or the Mac's MIDI server stuck after the desk was power cycled.

## Documentation

| File | What it covers |
|---|---|
| [docs/install.md](docs/install.md) | Installing the driver, the app and Logic's setup; troubleshooting |
| [docs/user-guide.md](docs/user-guide.md) | What every button, encoder, fader and display does |
| [docs/config.md](docs/config.md) | Settings and the config file, with every key |
| [docs/mapping.md](docs/mapping.md) | The desk to Mackie Control mapping, control by control |
| [docs/protocol.md](docs/protocol.md) | The Digi 002 control surface protocol, captured from the desk |
| [docs/development.md](docs/development.md) | For developers: the project brief, modules, status and conventions |

## Limits

- The protocol was captured from a Digi 002. The 002 Rack, 003 and 003 Rack share the
  driver and very likely the protocol, but have not been tried.
- The desk's audio side (sample rate, clock source, optical mode) is not touched; Audio
  MIDI Setup still handles that.
- The displays show 4 characters per strip, as the desk has; names are shortened or
  scrolled to fit.
- The app is not notarised, so the first launch needs the extra step described above.

The code, the protocol write-up and the development notes are in this repository for
anyone who wants to look further; see [docs/development.md](docs/development.md).
