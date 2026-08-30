#!/usr/bin/env bash
# Launches RumbleArena. Finds Godot 4.3, or explains how to point at it.
set -uo pipefail
cd "$(dirname "$0")"

find_godot() {
	# A path written into godot_path.txt beside this script wins.
	if [ -f godot_path.txt ]; then
		local pinned
		pinned="$(head -n1 godot_path.txt | tr -d '\r')"
		[ -x "$pinned" ] && { echo "$pinned"; return; }
	fi
	[ -n "${GODOT:-}" ] && [ -x "$GODOT" ] && { echo "$GODOT"; return; }

	local candidate
	for candidate in \
		"$(command -v godot 2>/dev/null)" \
		"$(command -v godot4 2>/dev/null)" \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/.local/bin/godot" \
		"/usr/local/bin/godot"
	do
		[ -n "$candidate" ] && [ -x "$candidate" ] && { echo "$candidate"; return; }
	done

	# Anything Godot-shaped next to this script or freshly downloaded.
	for candidate in ./Godot* "$HOME/Downloads"/Godot*; do
		[ -f "$candidate" ] && [ -x "$candidate" ] && { echo "$candidate"; return; }
	done
	echo ""
}

GODOT_BIN="$(find_godot)"
if [ -z "$GODOT_BIN" ]; then
	cat <<'MESSAGE'

  Could not find Godot 4.3.

  Download it from https://godotengine.org/download (Godot 4.3, standard
  version -- not .NET), then do ONE of these:

    * Put the Godot binary (or Godot.app) in this folder or /Applications, or
    * Create a file called godot_path.txt here whose only line is the full
      path to your Godot binary, or
    * Run this script with GODOT=/path/to/godot ./play.sh

MESSAGE
	exit 1
fi

# Forward+ needs Vulkan. On older machines or flaky drivers that fails outright,
# and the OpenGL path is the fallback rather than a dead end.
EXTRA=()
if [ "${1:-}" = "--compat" ]; then
	EXTRA=(--rendering-driver opengl3 --rendering-method gl_compatibility)
fi

# Godot has to have imported the assets and registered every class_name before
# the game is launchable: without that cache the autoloads fail to compile and
# nothing responds to input, while the arena still renders perfectly. The test
# is whether the cache MATCHES the scripts on disk, not merely whether a cache
# exists -- replacing a game folder by hand leaves the old one behind, and an
# old cache that has never heard of a new class is exactly as broken as none.
# If the checker is missing this install is mangled; fall back to the old
# "is there a cache at all" test rather than refusing to run.
cache_ready() {
	if [ -x ./tools/cache_is_current.sh ]; then
		./tools/cache_is_current.sh "$PWD"
	else
		[ -s ".godot/global_script_class_cache.cfg" ]
	fi
}

if ! cache_ready; then
	echo
	echo "  Preparing assets. This takes a minute or two, and only happens"
	echo "  when the game files have changed."
	"$GODOT_BIN" --headless --path "$PWD" --editor --quit > setup_log.txt 2>&1
	if cache_ready; then
		echo "  Ready."
	else
		# An import pass that fails still exits 0 and still leaves a .godot
		# behind, so "we ran it" is not evidence that it worked.
		echo
		echo "  Preparing the assets did not work, so the game would start with"
		echo "  nothing responding to input. Rather than launch it like that:"
		echo
		echo "    1. Delete the .godot folder here and run ./play.sh again."
		echo "    2. If that fails too, send me setup_log.txt from this folder."
		echo
		exit 1
	fi
fi

# One line if there is a newer version. Bounded and never fatal.
if [ -x ./update.sh ] && [ ! -f no_update_check.txt ]; then
	./update.sh --check 2>/dev/null || true
fi

echo
echo "  RumbleArena"
echo "  Using: $GODOT_BIN"
if [ ${#EXTRA[@]} -gt 0 ]; then
	echo "  Compatibility renderer (OpenGL)"
fi
echo "  Press A on a gamepad, or SPACE on the keyboard, to join."
echo
"$GODOT_BIN" --path "$PWD" "${EXTRA[@]}"
status=$?
if [ "$status" -ne 0 ] && [ ${#EXTRA[@]} -eq 0 ]; then
	echo
	echo "  Godot exited with an error. If it mentioned Vulkan, your GPU or its"
	echo "  drivers cannot run the default renderer. Try:  ./play.sh --compat"
	echo
fi
exit "$status"
