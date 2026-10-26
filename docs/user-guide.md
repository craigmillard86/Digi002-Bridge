# Digi 002 with Logic Pro: button guide

What every control on the desk does once the bridge is running. The desk works as a
Mackie Control for Logic, so each button does what the matching Mackie Control button
does in Logic. The source of truth for the mapping is `docs/mapping.md`; this guide
explains it from the user's side.

## Before you start

The bridge must be running, and Logic must have a Mackie Control set up on the
"003 MCU" port.

1. Open "002 Bridge" (see "Installing" below). It starts the bridge on its own, finds
   the desk's control port and creates the "003 MCU" port; the window shows whether
   the desk and Logic were found. The command line version, `digi002-bridge`, does the
   same without a window.
2. In Logic, once only: Control Surfaces > Setup > New > Install > Mackie Designs >
   Mackie Control, then set its Output Port and Input Port to "003 MCU". Then in
   Logic Pro > Settings > MIDI > Inputs tick "003 MCU" and untick "Avid 002 Port 3
   (Control)", or Logic shows names on the desk but ignores its buttons and faders.
   Logic remembers this.
3. Open Logic. The bridge connects to the desk only while Logic runs. About 5 seconds
   after Logic starts, the desk comes out of standby, the bridge clears every LED and
   display, then Logic sends its state and the faders, LEDs and displays catch up.

When Logic quits, the bridge wipes the desk, disconnects, and the desk goes back to
standby: the faders park at the bottom and the displays show "Digi 002 / Standby". Start
Logic again and it wakes. The desk can be switched off and on at any time; the bridge
notices it go and picks it up again when it is back.

## Channel strips

The eight strips are the eight tracks of the current fader bank in Logic. Page and Bank
move the bank (see Navigation).

| Control | What it does in Logic | What the desk shows |
|---|---|---|
| Fader | Track volume. Touching the fader tells Logic you have it, so Logic stops moving the motor until you let go. | The motor follows Logic's volume, including automation. |
| Encoder | The V-Pot: pan by default, or the send level, plug-in, EQ or instrument parameter chosen with the assignment buttons. In Flip mode it becomes the volume. | The ring follows Logic: a dot for pan, a bar from the left for levels, from the centre for boost/cut. The last LED lights green when the value is centred. |
| SEL | Selects the track, like clicking its name. Shift+SEL extends the selection; Option+SEL selects a single track. | LED on for selected tracks. |
| SOLO | Solo on/off. | LED on while soloed. |
| MUTE | Mute on/off. | LED on while muted. |
| Rec (the button beside Meter) + SEL | Hold Rec and press a strip's SEL to arm or disarm that track for recording. | The small red Record Ready LED above SEL is on while armed and flashes while Logic records. |
| Display above the strip | The track name, cut to 4 characters the way Pro Tools did it: "Audio 1" is "Aud1", "Master" is "Mstr". Settings can instead make long names scroll across the display, once or all the time. While you turn an encoder, the value shows for 1.5 seconds ("L23", "C", "-10."), then the name returns. In views where Logic shows only one line, that line is shown. | 4 characters per strip. |

The SEL LED is two-colour. Logic only uses green. With "Record-armed tracks light SEL
red" ticked in Settings, an armed track's SEL is red, and orange when it is also
selected.

## Encoder assignment buttons

These choose what the eight encoders control. Logic lights the button for the active
assignment, and display 9 (left of the sample rate LEDs) names it.

| Desk button | Logic (Mackie Control) | Encoders then control |
|---|---|---|
| Pan (left column) and Pan/Send (console view) | Pan | Pan of each track. Press again to step through surround parameters on surround tracks. |
| Send (left column) | Send | One send per encoder for the selected track; press again to step through send level, destination and pre/post. |
| Insert (left column) and Insert (console view) | Plug-in | Choose a plug-in slot, then its parameters, 8 at a time. Page with the Page buttons. |
| EQ | EQ | Channel EQ parameters of the selected track. |
| Dynamics | Instrument | Software instrument parameters of the selected track. |
| Display | Name/Value | Switches Logic's display between parameter names and values. On the desk this changes what the 4-character displays show. |

Pressing an assignment button a second time usually switches Logic between "one
parameter on every track" and "every parameter of the selected track". The displays
follow whichever view is active. The A–E buttons in the left column do whatever you
choose in Settings; see "A to E, Master Bypass, Master Faders" below.

## Navigation

| Desk button | What it does in Logic | LED |
|---|---|---|
| Page ◀ / ▶ | Bank left / right: the eight strips move by eight tracks. In plug-in and EQ views, pages through the parameters. | Logic lights it when there is more to page to. |
| Bank | Sets the arrow pad's ◀ ▶ to move by eight tracks (the default). | On when this mode is active. |
| Nudge | Sets the arrow pad's ◀ ▶ to move by one track. | On when this mode is active. |
| Arrow pad ◀ ▶ | Move the fader bank, by eight or one track per the mode above. While Logic's Zoom is on they move the cursor instead. | — |
| Arrow pad ▲ ▼ | Cursor up / down: moves the track selection, or scrolls, as Logic's own arrow keys do. | — |
| Zoom | Zoom mode: the arrow pad then zooms the Arrange area horizontally (◀ ▶) and vertically (▲ ▼). Press again to leave. | On while zoom mode is active. |
| Flip | Swaps the encoders and the faders: the faders take the encoder parameter (pan, send level, plug-in parameter) and the encoders take the volume. Useful for riding sends or automation on the faders. | On while flipped. |

## Display and utility buttons

| Desk button | What it does in Logic | LED |
|---|---|---|
| Enter | Enter: confirms a dialog or a value, like the Return key. | Logic lights it when there is something to confirm. |
| Undo | Undo. With Shift, Redo. | On when there is something to undo. |
| Esc | Cancel: closes a dialog or cancels an edit. | Lit while a dialog is open. |
| Shift / Add, Option / All, Ctl / Clutch, Comm | The four Mackie Control modifiers: Shift, Option, Control, Command. Hold one while pressing another button for its alternative function, exactly as in Logic's Mackie Control guide (for example Option+SOLO clears all solos, Shift+Undo is Redo, Option+SEL selects one track). | No LED on these buttons. |
| F1–F5 | Function keys F1–F5. Logic's default recalls screensets 1–5; you can give them any command in Logic > Control Surfaces > Controller Assignments. | No LED. |
| Mix, Edit, Plug-in (Windows section) | F6, F7, F8. Logic's default recalls screensets 6–8. To make them open the Mixer, the editors and the plug-in window, reassign F6–F8 in Controller Assignments. | On when Logic lights the F key. |
| Display | Name/Value: toggles Logic between showing parameter names and values on the surface. | Follows Logic. |

## Transport

| Desk button | What it does in Logic | LED |
|---|---|---|
| Rewind | Rewind. Hold to keep going; press Stop to stop. | No LED. |
| Fast Forward | Forward. | No LED. |
| Stop | Stop. Press twice to return to the start of the project or the cycle. | No LED. |
| Play | Play. Press during playback to pause. | No LED (the green mark is printed). |
| Rec | Record: starts recording on the armed tracks. | No LED (the red mark is printed). |
| RTZ | Return to zero: the bridge sends Stop twice, which takes Logic to the start of the project, or of the cycle when Cycle is on. If Logic is playing it stops first. | No LED. |
| Loop Play | Cycle on/off. | On while Cycle is on. |
| Quick Punch | Autopunch on/off: recording only happens inside the punch locators. | On while Autopunch is on. |
| Loop Rec | Replace mode on/off: new recordings replace what was there instead of making takes. | On while Replace is on. |

The transport buttons have no LEDs on this desk, so Logic's play and record state shows
on screen only.

## Meters and the right-hand displays

**Meter** switches the encoder rings between the V-Pot positions and Logic's channel
meters, the way Pro Tools used them. Each ring shows a bar for the level, a single LED
that holds the peak for a second and then falls one step at a time, and the red 15th LED
for two seconds after a clip. Press Meter again to see the pan or parameter positions.
Its LED is on while the rings show meters. Logic keeps sending the meters whether or not
the rings show them, so switching is instant.

The two displays above the sample rate LEDs show Logic's state:

| Display | Shows |
|---|---|
| 9 (left) | The current encoder assignment: Pan, Send, Plug, EQ, Inst or Trk. |
| 10 (right) | Logic's position: the bar number in bars/beats, or the hours in SMPTE. |

Settings > Position offers two more layouts: bar and beat on display 10 as "12.3" (hours
and minutes in SMPTE), or the bar on display 9 and the beat and division on display 10
as "3.1" (minutes and seconds). In that last layout the assignment name appears on
display 9 for a moment when it changes, then the bar comes back. The E button (SMPTE/
Beats by default) switches Logic between the two formats.

## A to E, Master Bypass, Master Faders

Mackie Control has no fixed meaning for these seven, so each does whatever you choose in
the app's Settings window (or the config file, see docs/config.md). Out of the box:

| Desk button | Does in Logic | LED |
|---|---|---|
| A | Marker: hold it and the arrow pad and Rewind/Forward go from marker to marker; Shift+A creates a marker. | On in marker mode. |
| B | Metronome on/off. | On while the click is on. |
| C | Save the project. | — |
| D | Scrub mode. | On in scrub mode. |
| E | Switches display 10 between bars/beats and SMPTE. | Follows Logic. |
| Master Bypass | User switch A: Logic leaves it free. Give it any command in Logic Pro > Control Surfaces > Controller Assignments (press Learn, then the button). | Follows Logic. |
| Master Faders | Global View: shows all tracks; press again to step through the mixer views. | On in global view. |

Any of them can instead be F1–F8, a transport button, a modifier, an encoder assignment,
a cursor key or nothing. Each can also be given a second function for while Shift is
held ("A with Shift" in Settings): for example A as Marker and Shift+A as Cycle. Without
a second function, Shift plus the button is Logic's own Shift variant, so Shift+A still
creates a marker. Standalone and the monitor section stay with the desk.

## Settings

002 Bridge > Settings… (⌘,) in the app. Changes apply at once; the desk is wiped and
refilled so you see the result straight away.

- General: start at login; menu bar only (no Dock icon); debug log. With the debug log
  off the window hides its log pane and shrinks to the status and the desk.
- Desk: how long to wait for the desk to wake after connecting; how long a changed value
  shows before the name returns; values light-on-dark; track names Pro Tools style
  ("Aud1") or just cut ("Audi"); long names scrolling; the position layout on displays
  9 and 10; meters on the rings at start; nav pad nudging at start; record-armed tracks
  lighting SEL red; keeping the desk's audio engine running while connected, which
  Avid's driver needs in order to deliver anything to the desk (leave it on).
- Buttons: the seven above, each with and without Shift.
- Notifications: a macOS notification when the desk is lost, when it is back, and when
  Logic runs but ignores the surface; a sound on connect and on loss.
- Host application: which program the desk is connected for, if not Logic.

The window also draws the desk as the bridge last sent it: faders, rings, names and LEDs.
It works with no desk attached, so Logic's side can be checked on its own.

## What the LEDs mean

LED behaviour is the same everywhere: a lit button means Logic reports that function as
active. A flashing LED is Logic asking for attention (the Record Ready LED flashes while
recording). The desk has no flashing of its own, so the bridge switches these LEDs on and
off every half second.

## Installing

The easiest way is the app: `tools/make-app.sh --install` builds "002 Bridge" into
/Applications. Open it, press Start (it starts on its own), and tick "Start at login".
Its window shows whether the desk and Logic are found and since when, and draws the
desk; the menu bar "002" item shows the state as a coloured dot (green connected, orange
standby, red not found, grey stopped) and offers Reconnect Desk, Restart Bridge, Reset
MIDI Server, opening Logic, the log and Settings. Reconnect Desk drops the desk and takes
it again, which is the cure when it stops following Logic (faders spring back after you
let go); the bridge notices that itself and does it for you unless Settings says not to. On first launch macOS may ask you to confirm, because the app is
not notarised: right-click it and choose Open.

For a background tool without a window, `tools/install.sh` builds the release version and copies it to
`/usr/local/bin/digi002-bridge`. Run it as `tools/install.sh --login` to also install a
launch agent, so the bridge starts when you log in and runs in the background; its log
is `~/Library/Logs/digi002-bridge.log`. To remove the launch agent:
`launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.digi002.bridge.plist` and
delete that file.

The Avid 003 Family driver (11.1.5) must be installed for the desk to appear; the bridge
only uses its MIDI control port.
