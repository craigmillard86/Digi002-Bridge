#!/bin/bash
# Keeps one capture session open so the desk stays awake, and takes commands from a file.
# Append lines to the command file to drive it: "> 90 05 49" sends, any other text is a
# label, "quit" ends the session.
#
# Usage: tools/probe-session.sh COMMAND_FILE OUT_LOG
#   then: echo "> 90 05 49" >> COMMAND_FILE
set -euo pipefail
commands=$1
out=$2
cd "$(dirname "$0")/.."
: > "$commands"
tail -n +1 -f "$commands" | .build/debug/capture log --echo --out "$out"
