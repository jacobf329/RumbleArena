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
