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

# One pass is not reliably enough. Godot quits after a single main-loop
# iteration, and with 24 MB of models and 2K textures to bring in, an import can
# still be outstanding when it does -- leaving a class cache that is missing
# whatever failed to compile in the meantime. It showed up here as an
# intermittent failure of this very check, which on a slower machine is not
# intermittent at all. So the launchers verify and repeat, and so does this.
echo "==> Import pass (what the launcher runs on first launch)"
attempt=0
until ./tools/cache_is_current.sh "$PROJECT"; do
	attempt=$((attempt + 1))
	if [ "$attempt" -gt 3 ]; then
		echo "FAILED: $((attempt - 1)) import passes did not produce a usable class cache."
		exit 1
	fi
	[ "$attempt" -gt 1 ] && echo "    pass $attempt (the previous one left work outstanding)"
	"$GODOT" --headless --path "$PROJECT" --editor --quit >/dev/null 2>&1
done
echo "    ready after $attempt pass(es)"

echo "==> Booting the game the way the launcher does"
output="$("$GODOT" --headless --path "$PROJECT" --quit-after 200 2>&1)"

if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script|Failed to instantiate" <<<"$output"; then
	echo "FAILED: the game does not boot cleanly from a fresh download."
	grep -E "SCRIPT ERROR|Parse Error|Failed to load script|Failed to instantiate" <<<"$output" | head -20
	exit 1
fi

echo "Cold start: clean."
