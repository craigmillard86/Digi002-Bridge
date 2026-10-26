# Settings and the config file

The bridge's settings live in one JSON file, shared by the app and the command line tool:

    ~/Library/Application Support/002 Bridge/config.json

The app's Settings window (002 Bridge > Settings…, or ⌘,) edits this file and applies
each change at once: the desk is wiped and refilled so a changed button or display
option shows straight away. The command line tool reads the file when it starts
(`digi002-bridge --config path` uses another file). No file means the defaults below.
Every key is optional; missing keys take their default, unknown keys are ignored, and a
file that cannot be parsed is reported and ignored.

```json
{
  "buttons": {
    "A": "marker",
    "B": "click",
    "C": "save",
    "D": "scrub",
    "E": "smpteBeats",
    "Master Bypass": "userA",
    "Master Faders": "globalView"
  },
  "shiftButtons": {},
  "nameStyle": "proTools",
  "nameScroll": "off",
  "timeDisplay": "bars",
  "valuesInverse": false,
  "valueDisplaySeconds": 1.5,
  "meterModeAtStart": false,
  "nudgeModeAtStart": false,
  "armedSelectRed": false,
  "deskWakeSeconds": 5,
  "holdAudioEngine": true,
  "reconnectWhenStuck": true,
  "hostBundleID": "com.apple.logic10"
}
```

## Buttons

Seven desk buttons have no fixed Mackie Control meaning, so each takes a function from
the `buttons` table: A, B, C, D, E, Master Bypass and Master Faders. Logic's state for
the chosen function lights the button's LED (all seven have one). The values are
Mackie Control functions as Logic understands them:

| Value | In Logic |
|---|---|
| `none` | Nothing |
| `marker` | Marker: hold for marker mode (the arrows and Rewind/Forward go by markers); Shift+Marker creates a marker |
| `nudge` | Nudge mode: the arrows nudge the selection |
| `click` | Metronome on/off |
| `save` | Save the project |
| `scrub` | Scrub mode |
| `globalView` | Global view (all tracks; press again for the mixer views) |
| `smpteBeats` | Switch the position display between SMPTE and bars/beats |
| `userA`, `userB` | User switches A and B. Logic leaves these unassigned; give them any command in Logic Pro > Control Surfaces > Controller Assignments (learn mode, then press the button) |
| `f1` … `f8` | F1 to F8 (screensets 1 to 8 by default) |
| `assignTrack`, `assignPan`, `assignSend`, `assignPlugin`, `assignEQ`, `assignInstrument` | Encoder assignment |
| `bankLeft`, `bankRight`, `channelLeft`, `channelRight` | Move the fader bank by 8 or by 1 |
| `flip`, `zoom`, `nameValue`, `enter`, `undo`, `cancel` | As the desk buttons of the same name |
| `shift`, `option`, `control`, `command` | A fifth modifier, if a modifier is more useful in reach |
| `cycle`, `drop`, `replace` | Cycle, autopunch, replace mode |
| `rewind`, `fastForward`, `stop`, `play`, `record` | Transport |
| `up`, `down`, `left`, `right` | Cursor keys |

The defaults give A–E the transport-area functions a Mackie Control has and the desk
lacks (Marker, Click, Save, Scrub, SMPTE/Beats), Master Faders the "Global View" button,
and Master Bypass a free user switch for whatever Logic command you assign it.

### With Shift

The `shiftButtons` table gives the same seven buttons a second function for while the
desk's Shift is held, with the same values. A button not in the table keeps its usual
function, which Logic then sees with Shift held (so Shift+A still creates a marker by
default). A button that is in the table sends its second function on its own: the bridge
releases Shift to Logic for that press and holds it again afterwards, so the second
function is not Logic's Shift variant of it. The LED follows the usual function, or
the Shift one if the usual function is `none`.

```json
  "shiftButtons": { "A": "click", "B": "cycle" }
```

## Options

| Key | Default | Meaning |
|---|---|---|
| `nameStyle` | `proTools` | How a track name is squeezed into 4 characters. `proTools` drops spaces, lowercase vowels and punctuation from the end first, so "Audio 1" is "Aud1" and "Master" is "Mstr". `plain` takes the first four characters: "Audi". |
| `nameScroll` | `off` | What a name longer than 4 characters does. `off`: it is shortened as above. `once`: when it appears it rests a second, scrolls across a character every 0.3 s, rests at the end, then settles on the short form. `always`: it keeps scrolling. A value shown on the strip pauses the scroll. Logic gives the bridge 7 characters of each name, so that is what scrolls. |
| `timeDisplay` | `bars` | How Logic's position shows on the right-hand displays. `bars`: display 10 shows the bar number (hours in SMPTE), display 9 the encoder assignment. `barsBeats`: display 10 shows bar and beat as "12.3" (hours and minutes as "1.02"); the dot is dropped when there is no room, as for bar 123 beat 4. `wide`: display 9 shows the bar (hours) and display 10 the beat and subdivision as "3.1" (minutes and seconds as "0215"); the assignment then shows on display 9 for `valueDisplaySeconds` when it changes. |
| `valuesInverse` | `false` | Show a changed value (pan, send level) light-on-dark for the moment it is displayed. |
| `valueDisplaySeconds` | `1.5` | How long a changed value stays on a strip's display before the name returns. 0.2 to 10. |
| `meterModeAtStart` | `false` | The encoder rings show Logic's meters from the start, until Meter is pressed. |
| `nudgeModeAtStart` | `false` | The nav pad's ◀ ▶ move the bank by one track from the start, until Bank is pressed. |
| `armedSelectRed` | `false` | A record-armed track lights its SEL button red (orange when also selected) as well as the small Record Ready LED. |
| `deskWakeSeconds` | `5` | How long the bridge waits after connecting before the desk accepts commands. The desk drops anything sent earlier. 1 to 30. |
| `holdAudioEngine` | `true` | Run a silent audio stream on the desk while connected. Avid's driver carries MIDI to the desk inside the audio stream, so nothing reaches the desk while no program runs its audio engine, and once the driver has stalled on that it stays stalled until the desk is power cycled. Pro Tools keeps the engine running all session; so does the bridge with this on. It does not stop Logic using the desk for audio at the same time. Turn it off only if the desk's audio device is used in a way that conflicts. |
| `reconnectWhenStuck` | `true` | Reconnect the desk by itself when it has stopped following Logic. The bridge notices this from the faders: a desk that is taking commands holds a fader where it was left, while one that has stopped drags it back after it is released. Two such snap-backs within a minute count, and the bridge then drops the desk and takes it again (about 15 seconds, after which it refills), which clears the state. If it happens again within five minutes the bridge gives up and says to power cycle the desk. With this off, the window and a notification say so and Reconnect Desk does the same by hand. |
| `hostBundleID` | `com.apple.logic10` | The application the desk is connected for. Any program that speaks Mackie Control on the "003 MCU" port works; the bridge connects the desk while that program runs. Find a bundle ID with `osascript -e 'id of app "Name"'`, or use "Choose App…" in Settings. |

## App settings

These are the app's own and are not in the file: start at login, menu bar only (no Dock
icon), debug log, which events notify (desk lost, desk back, host ignoring the surface),
and the sounds on connect and loss. With the debug log off the window hides its log pane
and shrinks to the status and the desk; the log file is still written, with state
changes and errors only. The command line tool has `--quiet` for the log level and
nothing else.

The window's drawing of the desk can be replaced by your own straight-down photo
(Settings > Desk picture > Choose Picture…). It is copied to desk.png in the same folder
as the config file, and desk-layout.json next to it says where each fader, ring, display
and LED sits as fractions of the picture's width and height; a guessed layout is written
the first time and is meant to be edited. "Use Schematic" goes back to the drawing.
