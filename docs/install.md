# Installing 002 Bridge

002 Bridge lets a Digi 002 (or 003) control surface work with Logic Pro as a Mackie
Control. It needs an Intel Mac running macOS 11 to 15, the desk connected by FireWire,
and Logic Pro.

## 1. Install Avid's driver

The desk only appears on the Mac through Avid's "003 Family" driver, version 11.1.5. It
is a free download from Avid (search for "003 Family driver 11.1.5 Mac"). Install it and
restart. On macOS 11 and later the installer may say the system extension was blocked:
open System Settings > Privacy & Security, allow it, and restart again.

Check it worked: open Audio MIDI Setup (in /Applications/Utilities), choose Window > Show
MIDI Studio, and look for an "Avid 002" or "Avid 003" device with a "Port 3 (Control)"
port.

## 2. Install the app

1. Unzip "002 Bridge" and drag "002 Bridge.app" into your Applications folder.
2. Open it. The first time, macOS will say it cannot check the app for malicious software,
   because it is not from the App Store and not notarised:
   - macOS 11 to 14: right-click the app, choose Open, then Open again in the dialog.
   - macOS 15: open it once (it will be refused), then go to System Settings >
     Privacy & Security, scroll down, and press "Open Anyway".
3. The window shows the desk, Logic and bridge status, and a picture of the desk. In
   002 Bridge > Settings… tick "Start at login" (macOS 13 or later) so the bridge is
   always there, and "Menu bar only" if you would rather not see it in the Dock. The
   same window sets what the A–E, Master Bypass and Master Faders buttons do, and the
   notifications and sounds; see docs/config.md.

## 3. Set up Logic, once

1. Open Logic Pro, then Logic Pro > Control Surfaces > Setup.
2. New > Install, choose Mackie Designs > Mackie Control, press Add.
3. Select the new device and set both Output Port and Input Port to "003 MCU".
4. Close the window. Logic remembers this.
5. Logic Pro > Settings > MIDI > Inputs: tick "003 MCU" and untick "Avid 002 Port 3
   (Control)". With "003 MCU" unticked Logic ignores every button and fader, while the
   displays still fill in, which is confusing. With the Avid control port ticked Logic
   reads the desk's raw messages as notes and keeps the desk awake after you quit.

Within a few seconds the desk wakes up, its faders move to Logic's positions and the
displays show the track names. When you quit Logic the desk goes back to standby.

## Using it

See the button guide (docs/user-guide.md in the project, or the copy included with the
app). In short: faders, SOLO, MUTE and SEL do what you expect; the encoders are pans or
whatever the Pan/Send/Insert/EQ/Dynamics buttons select; Meter puts Logic's meters on the
encoder rings; hold Rec (next to Meter) and press SEL to arm a track.

## If something does not work

- "Desk: not found": the desk is off, not on FireWire, or the Avid driver is not installed.
- "Logic Pro: running" but not "talking to the bridge": step 3 above is missing, or Logic
  has no project open.
- Names appear on the desk but buttons and faders do nothing in Logic: "003 MCU" is
  unticked in Logic Pro > Settings > MIDI > Inputs (step 5 above).
- The desk shows nothing, or stays awake after Logic quits: only one copy of the bridge
  may run. The app refuses to start with "another copy of the bridge is already running"
  if the command line tool or a second copy of the app is up; quit that one. If the desk
  was left half awake, turn it off and on again, wait for "Standby" on its display, then
  start the bridge.
- Logic has to see the "003 MCU" port appear; if it was open before the bridge started,
  it can take a few seconds to re-send its state.
- "Logic Pro: NOT answering the bridge": the bridge announced the desk to Logic and
  nothing came back, which a working Logic does within a fraction of a second. Open a
  project, and check the Mackie Control's ports and the MIDI Inputs tick as above. If the
  message instead says "quit it and open it again", the MIDI server restarted while Logic
  was open and took Logic's ports with it; reopening Logic is the only fix.
- "Desk: stopped following ... connecting again", or faders spring back to where they
  were after you let go of them while buttons still reach Logic: the desk has stopped
  taking commands but is otherwise fine. The bridge notices (two snap-backs within a
  minute) and reconnects the desk by itself, which clears it; the desk refills about 15
  seconds later. Reconnect Desk in the menu bar does the same by hand, and Settings has
  the switch for doing it automatically. If it keeps happening the bridge says to power
  cycle the desk. The cause is not known yet; it has been seen only after the bridge was
  started while the desk was already awake and its audio engine already running.
- "Desk: NOT taking commands", or buttons and faders from the desk reach Logic while
  the faders, LEDs, names and time on the desk stop following it: the desk has gone deaf.
  It happens when a program takes the desk within a few seconds of it being released,
  while it is still going to standby (the bridge now waits 10 seconds before any
  reconnect for this reason), and also when nothing is running the desk's audio engine,
  which Avid's driver needs to carry MIDI to the desk (the bridge keeps it running;
  Settings > "Keep the desk's audio engine running"). Once deaf, only a power cycle
  clears it: switch the desk off, wait for "Desk: not found", switch it on. The bridge
  then reconnects and refills it. The bridge stops sending to a deaf desk as soon as it
  notices, because switching the desk off while the driver's buffer to it is full crashes
  the Mac's MIDI server. If that happens anyway, every MIDI port disappears for a moment;
  the bridge restarts itself, and Logic needs to be reopened because it loses its ports:
  the app then shows "Logic Pro: NOT answering: quit it and open it again" and sends a
  notification.
  If none of that helps: Bridge > Reset MIDI Server and reopen Logic; if FireWire comes
  through a Thunderbolt adapter, unplug the adapter from the Mac, wait 10 seconds and plug
  it back in; restart the Mac with the desk on.
- Switching the desk off and on while the bridge runs is fine: the app shows "Desk: not
  found" while it is off, picks it up again a few seconds after it is on, and either wipes
  it (Logic closed) or fills it in (Logic open). If instead the desk ignores everything
  afterwards, see the previous point.
- The desk looks stuck while everything else is fine: Bridge > Reconnect Desk (⌘D)
  drops the connection and makes it again.
- The log in the app window (shown while "Debug log" is ticked in Settings) says what
  happened; Bridge > Copy Log puts it on the clipboard.
  The app also writes every message to ~/Library/Logs/002 Bridge.log (Bridge > Show Log
  File in Finder), with the previous launch kept as "002 Bridge.previous.log". Send that
  file along with any problem report.
