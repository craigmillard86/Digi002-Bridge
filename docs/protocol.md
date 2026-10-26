# Digi 002 control surface protocol

Captured from a Digi 002 (FireWire, Avid 003 Family driver 11.1.5) on the CoreMIDI
port "Avid 002 Port 3 (Control)". Untested on a 003 or 002 Rack.

All bytes are hex. "Surface to host" is what the desk sends when you use it.
"Host to surface" is what makes the desk move a fader or light an LED.
Each entry says whether it is **confirmed** (seen and repeated with a known cause)
or **unconfirmed** (seen once, or inferred from a pattern). Capture logs are in
`captures/`.

## Connection behaviour

| Behaviour | Status | Source |
|---|---|---|
| With no client connected to Port 3, the desk is in standby: fader motors are off and faders move freely. | confirmed | user observation |
| When a client connects to the Port 3 source/destination, the desk leaves standby and the motors engage, holding each fader at its last host-set position (bottom after power-on). | confirmed | user observation |
| Leaving standby takes a few seconds. Messages sent in the first moments after connecting can be missed. | confirmed | led-probe-1, fader-probe-2/3 |
| When the client disconnects, the desk returns to standby and clears LEDs it was told to light. | confirmed | user observation |
| "Connected" means a CoreMIDI client exists in the process that opened the port. Disconnecting the source (`MIDIPortDisconnectSource`) does not release the desk; only disposing the client (or the process exiting) does. The bridge therefore gives the desk its own client, created when Logic starts and destroyed when it quits. | confirmed | bridge-run-18/19, user observation |
| With two clients connected at once (two copies of the bridge) the desk never reaches standby and ignores commands, although it still sends its own events. Only one bridge may run; it refuses to start if a "003 MCU" port already exists. | confirmed | bridge-run-18/19 |
| When the Avid MIDI driver loads (the MIDI server starting with the desk present) the desk leaves standby by itself, and drops back about a minute later if no client connects. | confirmed | 25 Oct, app launch with Logic closed |
| The driver delivers MIDI to the desk only while the desk's audio engine is running: outgoing bytes go into a 128-byte ring that the kernel driver empties into the isochronous audio stream. When nothing runs the engine the ring fills, and the send routine (`MAFireWireMIDIDICE_Send` → `-[FW003Device send:viaPort:]` in MIDIServer) then sleeps 10 ms at a time, up to a second per message, before dropping it; every program sending to the desk queues behind that. Input from the desk is a separate timer and keeps working, so the desk looks half alive: buttons reach the host, nothing comes back. Seen after a desk power cycle (25 Oct) and after Logic quit and relaunched, stopping and restarting the engine (26 Oct). A power cycle of the desk resets it; a Mac restart always does. Running a silent audio stream on the desk (a Core Audio IOProc, as the bridge now does while connected) keeps the ring draining, which is what Pro Tools does by holding the engine all session. | observed 25–26 Oct; mechanism from the driver's send loop and docs/003-driver-discovery.md | MIDIServer samples, bridge log |
| The desk goes deaf if a client takes it within a few seconds of the previous client releasing it, while it is still going to standby (confirmed 26 Oct with a disconnect and reconnect 3 ms apart: buttons and faders still reach the host, nothing sent to it arrives, it does not even go to standby when released, and only a power cycle clears it). The same follows a bridge restart, the bridge being killed and relaunched, or the host quitting and reopening within seconds. The bridge waits 10 s after any release, and after the desk's ports appear, before connecting. | confirmed 26 Oct | bridge log, user observation |
| Switching a deaf desk off crashes MIDIServer: the driver's send routine is asleep in its full-ring loop and re-reads the port's ring pointers after the device is gone (`-[FW003Device send:viaPort:]+480`, crash reports 26 Oct 14:43 and 14:52). Every MIDI port vanishes until the server comes back; clients made before the crash stay blind. The bridge stops sending once it sees a slow send (the buffer is full), and restarts itself when its own port is missing. | confirmed 26 Oct | MIDIServer crash reports |
| When the desk is switched off the driver removes all its endpoints (not just marks them offline); when it is switched on it creates new ones with new refs. A stored endpoint ref is then useless, so the control port is looked up on every poll. | confirmed 25 Oct | source listing with desk off |
| The desk sends nothing while idle. | confirmed | 5 s idle log |
| A touched fader is released by the motors. On release the motor returns it to the last host-set position, so the host must echo moves back to keep a fader where it was left. | confirmed (behaviour); echo not yet tested | user observation |

## Faders

Fader N (1 to 8) uses MIDI channel 1 control changes: controller N−1 carries the
coarse 7 bits and controller N+31 (0x20 + N−1) carries the fine bits.

| Direction | Message | Meaning | Status |
|---|---|---|---|
| Surface to host | `B0 cc vv` then `B0 cc+20 ll` | position of fader cc+1. `vv` = coarse (00 to 7F), `ll` = fine | confirmed for all 8 (CC 00–07 / 20–27), with touch numbers matching, echo-test-2 |
| Surface to host | — | fine byte only takes multiples of 10 (00, 10 ... 70), so position is 10 bits: `vv << 3 \| ll >> 4` | confirmed, fader1-background |
| Surface to host | — | sent about every 30 ms while moving, coarse and fine in separate packets with the same timestamp | confirmed |
| Host to surface | `B0 cc vv cc+20 ll` | move fader cc+1. **Must use running status** (one `B0`, then both pairs) | confirmed for all 8: `B0 cc 7F cc+20 70` = top, `B0 cc 00 cc+20 00` = bottom (fader-probe-6, fader-motors) |
| Host to surface | `B0 cc vv B0 cc+20 ll` | ignored | confirmed (fader-probe-3, -6) |
| Host to surface | `B0 20 ll B0 00 vv` (fine first) | ignored | confirmed (fader-probe-6) |
| Host to surface | `E0 ll mm` (pitch bend, Mackie style) | ignored | confirmed (fader-probe-6) |

Open: whether the coarse byte alone (`B0 cc vv`) moves a fader. The desk does not report motor moves back as positions.

## Fader touch

| Direction | Message | Meaning | Status |
|---|---|---|---|
| Surface to host | `90 05 (40 + N−1)` | fader N touched (`40` = fader 1 ... `47` = fader 8) | confirmed for all 8, echo-test-2 |
| Surface to host | `90 05 (N−1)` | fader N released (`00` = fader 1 ... `07` = fader 8) | confirmed for all 8, echo-test-2 |
| Surface to host | — | each fader sends its own touch/release; two held at once give two touch messages | confirmed (faders 4 and 5), echo-test-2 |
| Surface to host | — | touch can flicker (release then touch again within ~10–50 ms) while a fader is moving | seen on fader 4, echo-test-2 |

## Buttons and LEDs

Channel strip buttons use note-on on channel 1. The note number is the row, the
velocity is `40` + (channel − 1) when pressed and (channel − 1) when released. Fader
touch uses the same scheme on row `05`.

| Row (note) | Control | Status |
|---|---|---|
| `00` | SEL | confirmed, channels 1–8, round1-strips |
| `01` | no switch; LED only: the red element of the SEL LED (see LEDs) | confirmed, sel-colours |
| `02` | SOLO | confirmed, channels 1–8, round1-strips |
| `03` | MUTE | confirmed, channels 1–8 (channel 6 on the second try, round2-encoders) |
| `04` | no switch; LED only: the small red Record Ready LED above SEL | confirmed, channels 1–8, small-led, small-led-channels |
| `05` | fader touch | confirmed, channels 1–8, echo-test-2 |

| Direction | Message | Meaning | Status |
|---|---|---|---|
| Surface to host | `90 rr (40 + ch−1)` | button pressed | confirmed |
| Surface to host | `90 rr (ch−1)` | button released | confirmed |
| Host to surface | `90 rr (40 + col)` | lights the LED of the button at row rr, column col | confirmed, see LEDs below |
| Host to surface | `90 rr col` | turns that LED off | confirmed, see LEDs below |

All buttons form one grid. The note number is the row and the low six bits of the
velocity are the column; bit 6 (`40`) is set while the button is held. Columns 0–7 are
the channel strips (rows `00` SEL, `02` SOLO, `03` MUTE, `05` fader touch), so for
those the column is the channel. Every button below was captured in rounds 1–4.

| Row | Col `0A` | Col `0B` | Col `0C` | Col `0D` | Col `0E` |
|---|---|---|---|---|---|
| `00` | Pan (left column) | EQ | Enter | Flip | Plug-in |
| `01` | Send (left column) | Dynamics | Undo | Master Faders | Mix |
| `02` | Insert (left column) | Insert (console view) | | Bank | Edit |
| `03` | A | Pan/Send | Rec (by Meter) | Nudge | Loop Play |
| `04` | B | Page ◀ | Meter | Zoom | Loop Rec |
| `05` | C | Page ▶ | | Nav pad left | Quick Punch |
| `06` | D | Master Bypass | | Nav pad right | RTZ |
| `07` | E | Esc | | Nav pad up | Rew |
| `08` | Shift | Display | | Nav pad down | FFW |
| `09` | Option | | | F1 (Utility) | Stop |
| `0A` | Control | | | F2 (Naming) | Play |
| `0B` | Command | | | F3 (Snapshot) | Rec (transport) |
| `0C` | | | | F4 (Fader Mute) | |
| `0D` | | | | F5 (Focus) | |

Empty cells: column `0C` rows `02` and `05`–`0D` are probably Standalone and the
monitor section (Alt Src to In 7-8, Alt Src to Mon, Mono, Mute). These were left out
on purpose, since they may change audio routing or the desk's mode.

Row `05` is shared: columns 0–7 are fader touch, columns `0A`–`0E` are buttons. A decoder
must check the column before treating `90 05` as touch.

## LEDs

A button's LED is addressed by the button's own grid position: send the "pressed"
message to light it and the "released" message to turn it off. LEDs stay lit only
while a client is connected (see Connection behaviour). Tested by sending each address
and naming it aloud (leds-1-strips, leds-2-other).

| Has an LED, lit correctly | No LED on the hardware |
|---|---|
| SEL, SOLO, MUTE on all 8 channels | Shift/Add, Option/All, Ctl/Clutch, Comm |
| Pan, Send, Insert (left column), A–E | Nav pad left, right, up, down |
| EQ, Dynamics, Insert, Pan/Send, Page ◀ ▶, Master Bypass, Esc, Display | F1–F5 |
| Enter, Undo, Rec (by Meter), Meter | RTZ, Rew, FFW, Stop, Play, Rec (transport) |
| Flip, Master Faders, Bank, Nudge, Zoom | |
| Plug-in, Mix, Edit, Loop Play, Loop Rec, Quick Punch | |

The green and red marks on Play and transport Rec are printed on the buttons, not LEDs.

Not tested: Standalone and the monitor section LEDs, the encoder rings, the L/R meter,
the sample rate LEDs.

### Two-colour SEL LEDs

The SEL LEDs have a green and a red element on separate rows (led-colours-1, sel-colours):

| Sent | SEL colour |
|---|---|
| `90 00 (40 + ch−1)` | green |
| `90 01 (40 + ch−1)` | red |
| both | orange |

Velocity bits `10` and `20` had no visible effect on SEL, MUTE or SOLO (no colour change,
no blinking). The Pro Tools 002 code confirms this: its LED routine only ever sets bit `40`
and it flashes LEDs by toggling them on a timer. MUTE and SOLO are single-colour. The same LED message on MIDI channels 2–16 (`91`–`9F 03 40`) lit nothing, so the desk only takes LED messages on channel 1 (led-midi-channels). Pro Tools flashes some LEDs (MUTE while
another track is soloed, Flip, Record Enable); no hardware blink has been found, so the
host presumably toggles them. The small red LED above each SEL is the Record Ready LED
(Getting Started guide, p. 35) and is row `04`: `90 04 (40 + ch−1)`.

## Encoders

| Direction | Message | Meaning | Status |
|---|---|---|---|
| Surface to host | `B0 (40 + ch−1) vv` | encoder ch turned. `vv` − 40 = steps: `41` `42` `43` clockwise, `3F` `3E` `3D` anticlockwise | confirmed, encoders 1–8, round2-encoders |
| Surface to host | — | encoders do not push; pressing sends nothing | round2-encoders |

The step size grows with turning speed. Mackie Control encoders also send relative
steps, but as sign + magnitude (bit 6 set = anticlockwise, low six bits = step count),
so the bridge must convert.

## Encoder rings

Source: the Digi002 "personality" bundle in Pro Tools 10.3.10 (reference/protools-10.3.10),
confirmed on the desk (sysex-ring-display, ring-red-displays). Each ring has 15 LEDs:
1–14 are single-colour, and the 15th, at the end of the arc, is green/red.

```
F0 13 00 00 ss hh ll F7
```

| Byte | Meaning |
|---|---|
| `ss` | bits 0–2: encoder 0–7. Bit `20`: 15th LED green. Bit `40`: 15th LED red (Pro Tools uses it for clipping). |
| `hh` | LEDs 8–14 as bits 0–6 |
| `ll` | LEDs 1–7 as bits 0–6 |

Any pattern can be set; the desk does not draw bars itself. Pro Tools draws a bar plus a
peak dot, and also uses the rings as meters. The bridge draws Logic's V-Pot ring modes
onto the arc (`Bridge.ring`), with Logic's centre flag on the green LED.

## Displays

Four characters per strip, same source and logs as the rings.

```
F0 13 00 40 ss mm hb c0 c1 c2 c3 F7
```

| Byte | Meaning |
|---|---|
| `ss` | strip. 0–7 are the channel displays; 8 and 9 are the two halves of the LCD above the sample rate LEDs. |
| `mm` | `78` normal text, `7C` inverse (light on dark). Bit 0 is bit 7 of `c0`. |
| `hb` | bit 7 of `c1`, `c2`, `c3` in bits 4, 2, 0 |
| `c0`–`c3` | the characters, low 7 bits. ASCII shows as expected; the rest of the 8-bit set is not mapped yet. |

Pro Tools keeps a 4-character cache per strip and only sends changes, and shows
temporary text with a timeout; the bridge does the same (name normally, a changed value
for 1.5 s). Pro Tools shortens names to 4 characters by dropping, in turn, non-ASCII
characters, spaces, lowercase vowels, `, # - .` and lowercase letters, from the end of the
name until it fits (`Bridge.abbreviate`). Strings in the bundle show it also used the
displays for status text: "Welcome!", "Session loading please wait", "Page x/x", "PanL",
"PanR", "L<>R", "Pre", "Post".

## Meters

Not found as a separate message. The Digi002 bundle has no other host-to-desk format:
Pro Tools showed meters on the encoder rings. The L/R meter LEDs by the master section
are not addressed yet; the `27`/`37` rows in the column-8 alias sweep lit one of them.

## Displays, encoder rings and meters: what was tried first

Kept as a record of what does not work. The displays show "Digi 002" / "Standby"
while no client is connected and go blank when a client connects. Nothing below lit a
ring, meter or display segment, and the desk sent nothing back to any of it.

| Tried | Idea | Log |
|---|---|---|
| `B0 10 2B`, `B0 10 06`, `B0 10 7F` | HUI V-Pot ring, channel 1 | hui-probe-1, ring-probe-2 |
| `F0 00 00 66 05 00 10 00 "TEST" F7` | HUI 4-character channel display 1 | hui-probe-1 |
| `F0 00 00 66 05 00 10 08 "TEST" F7` | HUI select-assign display | hui-probe-1 |
| `A0 00 0C`, `A0 00 1C` | HUI meter, channel 1 left/right clip | hui-probe-1 |
| `B0 40 7F`, `B0 40 40`, `B0 40 01` | ring on the encoder's own CC | ring-probe-2 |
| `F0 7E 7F 06 01 F7` | universal identity request (no reply) | ring-probe-2 |
| `B0 cc 7F` for every cc 08–1F, 28–3F, 48–77 | any plain CC on channel 1 | cc-sweep |
| `B0 cc 7F cc+20 70` for cc 08–1F and 40–47 | a paired CC with running status, like the faders | cc-pairs |
| `E0`, `C0 01`–`08`, `D0`, `A0 00`–`0F` with values 40 and 7F | pitch bend, program change, channel pressure, poly aftertouch | other-status |
| `9n 03 40` for n = 1–F | LED on another MIDI channel | led-midi-channels |

HUI formats came from theageman's HUI notes (stash.reaper.fm/12332/HUI.pdf). The 002
shares HUI's fader and encoder input formats but not its LED, display or meter formats.
Do not send the HUI ping `90 00 00`: on the 002 it means SEL 1 released / SEL 1 LED off.

### Out-of-range note addresses alias onto existing LEDs

Note-on to grid positions that have no button lights *something*, but not a new LED:
the desk folds the address onto LEDs that already have their own address. This is a
side effect, not a usable format (column-sweep, led-map-1).

| Sent | What lit | That LED's real address |
|---|---|---|
| `90 04 49` (row 04, col 09) | Page ◀ | `90 04 4B` |
| `90 05 49` (row 05, col 09) | encoder 4 ring, LED 1 | none known |
| col 08 rows `27`, `2A`–`2D`, `32`–`35`, `37`, `3A`–`3D`, and the same + 40 | ring LEDs on encoders 8, 7, 6, 5 (one per row in a run of four), `27`/`37` a meter LED and an "L" | none known |
| col 09 rows `05`, `28`, `2B`–`2E`, `33`–`36`, `38`, `3B`–`3E` | the same pattern one row later: `3C`/`3D`/`3E` = ring LED 1 on encoders 8/7/6, `34`/`35`/`36` = LED 3 on 8/7/6, `2E` = LED 2 on encoder 6 | none known |
| `90 06 49` (row 06, col 09) | Pan (left column) | `90 00 4A` |
| rows `0E`–`27`, col 0 | assorted SEL / SOLO / MUTE LEDs on various channels | strip rows |
| rows `28`–`2F`, col 0 | Console View buttons (Pan, Send, ...) | col `0B` |

Hardware notes from the user: each encoder ring has 15 LEDs, and some LEDs have more than
one colour (the SEL LEDs, see above; the ring's last LED is red per the manual). That is about 128 LEDs with
no address in the note grid. The aliasing shows the ring LEDs live in the same LED matrix
as the buttons: rows above `0D` wrap, and rows 40–7F repeat 00–3F (ring-col8, ring-col9,
ring-hits). The real ring message is the SysEx above.

## Where the formats came from

Avid's 11.1.5 driver package (reference/avid-driver-11.1.5) only moves console bytes
between FireWire and the "Port 3 (Control)" MIDI port; `SendMIDI` is its one path to the
desk, which is why every surface format is MIDI on that port. The surface code shipped
inside Pro Tools as `Controllers/Digi002.bundle` (internal name "Hedges"); the copy in
reference/protools-10.3.10 is from Pro Tools 10.3.10, the last version to support the
002. Its i386 code builds exactly four host-to-desk messages: the LED note, the fader CC
pair, the ring SysEx and the display SysEx. The bundle's resource fork holds the desk's
firmware images (sys v1.21, fader v1.05a, boot b1.00, plus 002 Rack versions); the fader
controller is an MSP430. No firmware-update message is built by this bundle, so the
messages above are safe to send.

## Test queue

Probes not run yet, cheapest first. Each one either finds an address or rules one out.

| # | Probe | Looking for |
|---|---|---|
| 1 | Display strips 10 and up | any further display segments |
| 2 | Display characters `80`–`FF` | the desk's own character set (bar graphs, arrows) |
| 3 | Ring with both `20` and `40` set | orange on the 15th LED |
| 4 | Note-on rows `0E`–`3F` in columns `00`–`07` and `0A`–`0E` | the L/R meter and other unaddressed LEDs |


## Not yet captured

Host to surface: the L/R meter, the display character set.
Surface to host: Standalone and the monitor section (left out on purpose).
