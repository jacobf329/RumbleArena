#!/usr/bin/env bash
# Double-clickable updater for macOS. Finder runs this from the user's home
# directory, so it has to find its own folder first.
cd "$(dirname "$0")" || exit 1
./update.sh "$@"
echo
echo "Press return to close."
read -r _
