#!/usr/bin/env bash
# Collects everything I would need to work out why the game will not run, and
# saves it to one file you can send me. Reads only; changes nothing.
set -uo pipefail
cd "$(dirname "$0")"
OUT="$PWD/diagnostics.txt"

echo
echo "  Collecting diagnostics..."

{
	echo "RumbleArena diagnostics - $(date)"
	echo "Folder: $PWD"
	echo "System: $(uname -a)"
	echo

	echo "== Godot =="
	GODOT_BIN=""
	if [ -f godot_path.txt ]; then
		pinned="$(head -n1 godot_path.txt | tr -d '\r')"
		[ -x "$pinned" ] && GODOT_BIN="$pinned"
	fi
	[ -z "$GODOT_BIN" ] && [ -n "${GODOT:-}" ] && [ -x "${GODOT}" ] && GODOT_BIN="$GODOT"
	[ -z "$GODOT_BIN" ] && command -v godot >/dev/null 2>&1 && GODOT_BIN="$(command -v godot)"
	for c in ./Godot*; do [ -z "$GODOT_BIN" ] && [ -x "$c" ] && GODOT_BIN="$c"; done
	if [ -n "$GODOT_BIN" ]; then
		echo "Found: $GODOT_BIN"
		echo "Version: $("$GODOT_BIN" --version 2>&1 | head -1)"
	else
		echo "Found: NONE - this is the problem."
	fi
	echo

	echo "== Asset cache =="
	if [ -s .godot/global_script_class_cache.cfg ]; then
		echo "Cache file: present"
		if ./tools/cache_is_current.sh "$PWD"; then
			echo "Cache state: current"
		else
			echo "Cache state: STALE - does not match the scripts on disk."
		fi
	else
		echo "Cache file: MISSING - the assets were never prepared."
	fi
	echo

	echo "== Version installed =="
	[ -f version.json ] && cat version.json || echo "version.json: absent"
	echo

	echo "== Files present =="
	for f in project.godot play.sh update.sh src scenes assets tools tests; do
		[ -e "$f" ] && echo "  ok      $f" || echo "  MISSING $f"
	done
	echo

	echo "== Last asset-preparation log =="
	[ -f setup_log.txt ] && cat setup_log.txt || echo "setup_log.txt: absent"
	echo

	echo "== A fresh run of the game, first 200 lines =="
	[ -n "$GODOT_BIN" ] && "$GODOT_BIN" --headless --path "$PWD" --quit-after 120 2>&1 | head -200
} > "$OUT" 2>&1

echo "  Saved to: $OUT"
echo "  Send me that file and I can tell you exactly what went wrong."
echo
