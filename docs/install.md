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
3. The window shows the desk, Logic and bridge status. Tick "Start at login" (macOS 13 or
   later) so the bridge is always there.

## 3. Set up Logic, once

1. Open Logic Pro, then Logic Pro > Control Surfaces > Setup.
2. New > Install, choose Mackie Designs > Mackie Control, press Add.
3. Select the new device and set both Output Port and Input Port to "003 MCU".
4. Close the window. Logic remembers this.

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
- The log in the app window shows what happened; Bridge > Copy Log puts it on the clipboard.
