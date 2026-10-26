# Changes

## Unreleased

- The bridge keeps the desk's audio engine running with a silent stream while it is
  connected. Avid's driver delivers MIDI to the desk only inside the audio stream, so
  without this Logic quitting, or the desk being switched on after the Mac, could leave
  the desk deaf (buttons still reached Logic, faders and LEDs stopped following it) until
  the desk was power cycled. Pro Tools avoids it the same way. Off switch in Settings.
- The bridge waits 10 seconds after releasing the desk, or after the desk is switched
  on, before connecting to it. Taking the desk while it is still going to standby left
  it deaf (buttons reached Logic, nothing came back) until a power cycle.
- A deaf desk is now noticed from the time a send takes, shown as "NOT taking commands"
  with a notification, and nothing more is sent to it, which keeps the MIDI server from
  crashing when the desk is then switched off.
- If the MIDI server does go away, the bridge restarts itself instead of sitting with a
  dead port list.
- A desk that has stopped following Logic is now caught and cleared. The desk's motors
  hold each fader where the host last put it, so a desk that has stopped taking commands
  drags a fader back after it is released instead of holding it. Two such snap-backs
  within a minute, and the bridge drops the desk and takes it again, which clears the
  state (quitting and reopening the bridge did the same by hand). The window and the
  menu bar say "stopped following ... connecting again", a notification says so, and
  Settings has the off switch. If it happens again within five minutes the bridge gives
  up and says to power cycle the desk.
- Logic's burst of device queries when a surface appears (five in a fifth of a second)
  is answered once rather than five times; each answer made Logic re-send its whole
  state to the desk.
- The bridge re-announces itself to a quiet Logic less eagerly: after 20 seconds of
  silence rather than 5, and at most once a minute.
- The log file is written from the bridge's own thread, so the last lines of a quit
  (the desk being wiped and released) are in it.
- A Logic that has gone deaf is now caught. Logic answers the bridge's surface
  announcement within milliseconds; when it does not (its MIDI ports died with a MIDI
  server restart, no project is open, or the surface is not set up) the window says so,
  the menu bar dot goes red, and a notification says what to do. After a MIDI server
  restart that is "quit Logic and open it again", which is the only cure. The bridge
  re-announces itself whenever the desk sends events to a Logic that has been silent.
- The app's port list could go stale for good when its first CoreMIDI call was made off
  the MIDI thread, so a desk switched on after the app was not found. Fixed.
- Start failures now log the real MIDI error.

## 0.1 (25 October 2026)

First release. A Digi 002 control surface works with Logic Pro as a Mackie Control,
in both directions, through Avid's 003 Family driver. No Pro Tools needed.

**Working on the desk**

- Faders 1–8 with touch, following Logic's volume and automation.
- Encoders as V-Pots (pan, sends, plug-in, EQ, instrument) with the LED rings following
  Logic; Flip; Logic's meters on the rings with peak hold and clip (Meter button).
- SEL, SOLO, MUTE, record arm (hold Rec and press SEL), nav pad with Bank/Nudge/Zoom,
  Undo, Enter, Esc, Shift/Option/Control/Command, F1–F5, Mix/Edit/Plug-in as F6–F8,
  transport, Loop Play (Cycle), Quick Punch (Autopunch), Loop Rec (Replace), RTZ.
- Displays: track names shortened as Pro Tools did ("Aud1"), or cut, or scrolling;
  values shown for a moment while an encoder turns; the encoder assignment and the song
  position on the two right-hand displays, in three layouts.
- A, B, C, D, E, Master Bypass and Master Faders are configurable (markers, click, save,
  scrub, cycle, screensets, user switches, transport and more), each with a second
  function for while Shift is held.
- The desk wakes when Logic starts and goes to standby when Logic quits. Switching the
  desk off and on while the bridge runs is noticed and recovered.

**The app**

- Window with desk, Logic and bridge status, a live drawing of the desk (or your own
  photo with the state drawn over it), Start/Stop, Restart, Reconnect Desk, and a log.
- Menu bar item with the state as a coloured dot and the quick actions.
- Settings: start at login, menu bar only, debug log, every desk option above, the
  button functions, notifications (desk lost, desk back, Logic ignoring the surface)
  and sounds. Settings are kept in `~/Library/Application Support/002 Bridge/config.json`.
- A command line version, `digi002-bridge`, for running without a window.

**Known limits**

- Tested on a Digi 002 only; the 002 Rack, 003 and 003 Rack are untried.
- Intel Macs on macOS 11 to 15 only; the app is not notarised, so the first launch needs
  right-click > Open (macOS 11–14) or Privacy & Security > Open Anyway (macOS 15).
- The desk's audio settings (sample rate, clock, optical mode) are not covered.
- If the desk is power cycled while the Mac is up, Avid's driver can wedge the Mac's
  MIDI server; Bridge > Reset MIDI Server or a restart with the desk on fixes it.
