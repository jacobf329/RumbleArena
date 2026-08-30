#!/usr/bin/env bash
# Verifies the game boots from a genuinely fresh download.
#
# A freshly extracted copy has no .godot folder, so Godot has neither imported
# the assets nor built its global class cache. Launching the game in that state
# leaves every class_name type unresolved, the autoloads fail to compile, and
# nothing responds to input -- while the arena still renders, so it looks like a
# working game that ignores the controller.
#
# The normal test run could never catch this: its first step is an import pass,
# which builds the very cache whose absence is the bug. This check deletes the
# cache first, then follows exactly what the launcher does.
set -uo pipefail
cd "$(dirname "$0")/.."
PROJECT="$PWD"
GODOT="${GODOT:-godot}"

echo "==> Cold start: removing .godot to simulate a fresh download"
rm -rf .godot

echo "==> Import pass (what the launcher runs on first launch)"
"$GODOT" --headless --path "$PROJECT" --editor --quit >/dev/null 2>&1

if [ ! -f ".godot/global_script_class_cache.cfg" ]; then
	echo "FAILED: the import pass did not produce a global class cache."
	exit 1
fi

echo "==> Booting the game the way the launcher does"
output="$("$GODOT" --headless --path "$PROJECT" --quit-after 200 2>&1)"

if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script|Failed to instantiate" <<<"$output"; then
	echo "FAILED: the game does not boot cleanly from a fresh download."
	grep -E "SCRIPT ERROR|Parse Error|Failed to load script|Failed to instantiate" <<<"$output" | head -20
	exit 1
fi

echo "Cold start: clean."
