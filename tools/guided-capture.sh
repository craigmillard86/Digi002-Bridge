#!/bin/bash
# Guided capture: speaks each control name from STEPS_FILE, writes it to the log as a
# LABEL, then waits for the user to press it. Fader echo is on so faders stay put.
#
# Usage: tools/guided-capture.sh STEPS_FILE OUT_LOG [SECONDS_PER_STEP]
# STEPS_FILE has one control name per line, spoken as written. Blank lines and lines
# starting with # are skipped. A line of the form "name | ON HEX | OFF HEX" sends ON HEX,
# speaks the name, waits, then sends OFF HEX (used to test LEDs and motors).
set -euo pipefail
steps=$1
out=$2
per=${3:-3}
cd "$(dirname "$0")/.."
{
    sleep 6            # the desk takes a few seconds to leave standby
    say "starting"
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        if [[ "$name" == *"|"* ]]; then
            IFS='|' read -r label on off <<< "$name"
            echo "$label"
            echo "> $on"
            say "$label"
            sleep "$per"
            echo "> $off"
            continue
        fi
        echo "$name"
        say "$name"
        sleep "$per"
    done < "$steps"
    say "done"
    echo quit
} | .build/debug/capture log --echo --out "$out"
