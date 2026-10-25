# Digi 002 to Logic (Mackie Control) button mapping

What each desk control does in Logic through the bridge. The source of truth is
`Bridge.buttonMap`, `Bridge.shiftButtonMap` and `Bridge.note(for:)` in
`Sources/BridgeCore/Bridge.swift`; keep this table in step with them. "LED" means Logic's state for that function is shown on
the desk button. LEDs Logic asks to flash are toggled by the bridge every 0.5 s.

## Channel strips

| Desk | Logic (MCU) | LED |
|---|---|---|
| Fader 1–8 | channel fader, with touch | motor follows Logic |
| Display 1–8 | Logic's LCD, squeezed to 4 characters: the track name (abbreviated as Pro Tools did, "Audio 1" → "Aud1", or cut, or scrolling, per the config), or a changed value for 1.5 s | — |
| Encoder 1–8 | V-Pot (pan by default) | ring follows Logic's V-Pot ring (or the meter, see Meter); Logic's centre flag lights the last LED green |
| SEL 1–8 | Select | yes |
| SOLO 1–8 | Solo | yes |
| MUTE 1–8 | Mute | yes |
| hold Rec (by Meter) + SEL n | Record arm channel n | the small Record Ready LED above SEL |
| Meter | toggles the rings between V-Pot positions and Logic's channel meters: a bar for the level, a dot that holds the peak for 1 s then falls, and the red 15th LED for 2 s after a clip (how Pro Tools used them) | shows meter mode |
| Display 9 (left of the sample rate LEDs) | the V-Pot assignment Logic has lit: Pan, Send, Plug, EQ, Inst, Trk | — |
| Display 10 | Logic's position: the bar number in bars/beats, the hours in SMPTE. The config's `timeDisplay` can make it bar.beat, or spread bar and beat.division over displays 9 and 10 (docs/config.md) | — |

## Navigation

| Desk | Logic (MCU) | LED |
|---|---|---|
| Page ◀ / ▶ | Bank left / right (8 tracks) | yes, if Logic lights it |
| Bank | nav pad ◀ ▶ move the bank by 8 tracks (default) | shows the mode |
| Nudge | nav pad ◀ ▶ move the bank by 1 track | shows the mode |
| Nav pad ◀ / ▶ | Bank or Channel left/right per the mode above; cursor left/right while Logic's Zoom is on | — |
| Nav pad ▲ / ▼ | Cursor up / down | — |
| Zoom | Zoom (then the nav pad zooms) | yes |
| Flip | Flip | yes |

## Assignment, display and utilities

| Desk | Logic (MCU) | LED |
|---|---|---|
| Pan (left column), Pan/Send (console view) | Assign Pan | yes |
| Send (left column) | Assign Send | yes |
| Insert (left column), Insert (console view) | Assign Plug-in | yes |
| EQ | Assign EQ | yes |
| Dynamics | Assign Instrument | yes |
| Display | Name/Value | yes |
| Enter | Enter | yes |
| Undo | Undo | yes |
| Esc | Cancel | yes |
| Shift, Option, Control, Command | Shift, Option, Control, Cmd/Alt | — |
| F1–F5 | F1–F5 | — |
| Mix, Edit, Plug-in (Windows) | F6, F7, F8 | yes |

## Transport

| Desk | Logic (MCU) | LED |
|---|---|---|
| Loop Play | Cycle | yes |
| Quick Punch | Drop (autopunch) | yes |
| Loop Rec | Replace | yes |
| Rew, FFW, Stop, Play, Rec | Rewind, Fast Forward, Stop, Play, Record | — |
| RTZ | Stop pressed twice: Logic returns to the project (or cycle) start | — |

## Configurable buttons

These have no fixed Mackie Control meaning and take their function from the config
file (docs/config.md). Defaults:

| Desk | Logic (MCU) | LED |
|---|---|---|
| A | Marker (hold for marker mode; Shift+A creates a marker) | yes |
| B | Click (metronome) | yes |
| C | Save | yes |
| D | Scrub | yes |
| E | SMPTE/Beats (position display format) | yes |
| Master Bypass | User switch A: assign any command in Logic's Controller Assignments | yes |
| Master Faders | Global View | yes |

Each can also have a second function for while Shift is held (`shiftButtons` in the
config); by default Shift plus the button is Logic's Shift variant of its function.

Standalone and the monitor section stay with the desk.
