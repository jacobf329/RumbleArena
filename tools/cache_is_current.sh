#!/usr/bin/env bash
# Is Godot's asset cache current for the project at $1?
#
#   exit 0 = ready to play    exit 2 = stale, re-import first
#
# "Does .godot exist" was the old test, and it is wrong: a cache only means the
# assets are prepared if it matches the scripts actually on disk. Replacing a
# game folder by hand leaves the old cache in place, and a cache that has never
# heard of a class the code now references makes every script that touches it
# fail to compile -- autoloads included, so nothing responds to input while the
# arena still renders perfectly. That is not a state a launcher should start.
set -uo pipefail

PROJECT="${1:-.}"
CACHE="$PROJECT/.godot/global_script_class_cache.cfg"

[ -s "$CACHE" ] || exit 2

# Every class_name the project declares is a name the cache has to know.
missing=0
while IFS= read -r name; do
	[ -n "$name" ] || continue
	# Quoted, so a class called Fighter is not satisfied by FighterState.
	grep -q "\"$name\"" "$CACHE" || { missing=1; break; }
done < <(grep -rhoE '^[[:space:]]*class_name[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
	--include='*.gd' "$PROJECT" 2>/dev/null \
	| sed -E 's/.*class_name[[:space:]]+//' | sort -u)
[ "$missing" = 1 ] && exit 2

# A source newer than the cache means content landed after it was built:
# imported .glb and .png live in .godot too, and a missing one fails at load
# rather than at compile.
#
# Whitelisted by extension rather than "everything except X". Godot rewrites
# .import files as part of importing, so anything-newer-than-the-cache is
# permanently true the moment an import finishes -- a check that can never pass
# is worse than no check, because it sends the launcher round the same loop
# every single launch.
newer="$(find "$PROJECT" -type f -newer "$CACHE" \
	-not -path "*/.godot/*" -not -path "*/.git/*" \
	\( -name '*.gd' -o -name '*.tscn' -o -name '*.tres' -o -name '*.gdshader' \
	   -o -name '*.glb' -o -name '*.gltf' -o -name '*.png' -o -name '*.jpg' \
	   -o -name '*.svg' -o -name '*.ogg' -o -name '*.wav' -o -name 'project.godot' \) \
	-print -quit 2>/dev/null)"
[ -n "$newer" ] && exit 2

exit 0
