#!/usr/bin/env bash
# Gets the latest version of the game. macOS and Linux; Windows uses
# "Update RumbleArena.bat".
#
#   ./update.sh            update if there is anything new
#   ./update.sh --force    re-download even if already current
#   ./update.sh --check    print one line if an update exists, then exit
#
# Re-execs itself from a temp copy, because bash reads a script incrementally as
# it runs: replacing this file mid-update would have the shell resume at a byte
# offset into different text. Running from a copy makes the whole install
# replaceable, this script included.
set -uo pipefail

OWNER="jacobf329"
REPO="RumbleArena"
BRANCH="claude/godot-ninja-game-96kjrj"
API="https://api.github.com/repos/$OWNER/$REPO"

# Everything the repository does not own, and so must survive an update.
KEEP=(".godot" "godot_path.txt" "version.json" "no_update_check.txt")

if [ "${RA_UPDATE_STAGED:-}" != "1" ]; then
	PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	staged="$(mktemp -t rumblearena_update.XXXXXX)"
	cp "$PROJECT/update.sh" "$staged" && chmod +x "$staged" || {
		echo "Could not stage the updater." >&2
		exit 1
	}
	RA_UPDATE_STAGED=1 RA_PROJECT="$PROJECT" "$staged" "$@"
	status=$?
	rm -f "$staged"
	exit "$status"
fi

PROJECT="$RA_PROJECT"
FORCE=0
CHECK=0
RECORD=0
for arg in "$@"; do
	case "$arg" in
		--force) FORCE=1 ;;
		--check) CHECK=1 ;;
		--record) RECORD=1 ;;
	esac
done

# --- Reading GitHub's answer without a JSON parser on the machine ---

first_field() {  # first_field <json> <key>
	printf '%s' "$1" | grep -m1 "\"$2\"" | sed -e 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"//' -e 's/".*//'
}

remote_head() {
	curl -fsSL --max-time "${1:-20}" -H "Accept: application/vnd.github+json" \
		"$API/commits/$BRANCH" 2>/dev/null
}

local_sha() {
	[ -f "$PROJECT/version.json" ] || return 0
	first_field "$(cat "$PROJECT/version.json")" "sha"
}

write_version() {  # write_version <sha> <subject>
	cat > "$PROJECT/version.json" <<JSON
{
  "sha": "$1",
  "subject": "$2",
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "branch": "$BRANCH"
}
JSON
}

# --- Check and record modes: quiet, bounded, never fatal ---

if [ "$CHECK" = 1 ] || [ "$RECORD" = 1 ]; then
	json="$(remote_head 5)" || exit 0
	[ -n "$json" ] || exit 0
	sha="$(first_field "$json" "sha")"
	subject="$(first_field "$json" "message" | sed 's/\\n.*//')"
	[ -n "$sha" ] || exit 0
	if [ "$RECORD" = 1 ]; then
		write_version "$sha" "$subject"
		exit 0
	fi
	installed="$(local_sha)"
	if [ -n "$installed" ] && [ "$installed" != "$sha" ]; then
		echo
		echo "   An update is available: $subject"
		echo "   Quit the game and run ./update.sh to get it."
	fi
	exit 0
fi

echo
echo "   ============================="
echo "     RumbleArena - update"
echo "   ============================="
echo

# A clone belongs to git; only a downloaded zip is ours to overwrite.
if [ -d "$PROJECT/.git" ]; then
	echo "   This copy is a git clone, so git owns it. Update it with:"
	echo
	echo "       git -C \"$PROJECT\" pull"
	echo
	echo "   Overwriting a clone's files from a zip would strip its history and"
	echo "   throw away anything you had changed, so this stops here."
	exit 1
fi

for tool in curl unzip; do
	command -v "$tool" >/dev/null 2>&1 || { echo "   Needs '$tool', which is not installed." >&2; exit 1; }
done

json="$(remote_head 20)"
if [ -z "$json" ]; then
	echo "   Could not reach GitHub. Check your connection and try again."
	echo "   Nothing was changed."
	exit 1
fi
sha="$(first_field "$json" "sha")"
subject="$(first_field "$json" "message" | sed 's/\\n.*//')"
installed="$(local_sha)"

if [ -n "$installed" ]; then
	echo "   Installed: ${installed:0:7}"
else
	echo "   Installed: unknown (this copy predates the updater)"
fi
echo "   Latest:    ${sha:0:7}  $subject"
echo

if [ -n "$installed" ] && [ "$installed" = "$sha" ] && [ "$FORCE" = 0 ]; then
	echo "   Already up to date."
	exit 0
fi

# What the update is bringing, rather than just "done".
if [ -n "$installed" ]; then
	compare="$(curl -fsSL --max-time 20 -H "Accept: application/vnd.github+json" \
		"$API/compare/$installed...$sha" 2>/dev/null)"
	if [ -n "$compare" ]; then
		# The response carries base_commit and merge_base_commit before the list
		# proper, and their messages match the same grep. total_commits says how
		# many of the trailing matches are the real ones.
		total="$(printf '%s' "$compare" | grep -m1 -o '"total_commits"[[:space:]]*:[[:space:]]*[0-9]*' \
			| grep -o '[0-9]*$')"
		[ -n "$total" ] || total=0
		[ "$total" -gt 12 ] && total=12
		subjects="$(printf '%s' "$compare" \
			| grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' \
			| sed -e 's/.*"message"[[:space:]]*:[[:space:]]*"//' -e 's/"$//' -e 's/\\n.*//' \
			| tail -n "$total")"
		if [ -n "$subjects" ]; then
			echo "   What you are getting:"
			while IFS= read -r line; do
				[ -n "$line" ] && echo "     - $line"
			done <<< "$subjects"
			echo
		fi
	fi
fi

stage="$(mktemp -d -t rumblearena_stage.XXXXXX)"
trap 'rm -rf "$stage"' EXIT

echo "   Downloading (about 20 MB)..."
if ! curl -fsSL --max-time 300 -o "$stage/source.zip" \
		"https://codeload.github.com/$OWNER/$REPO/zip/refs/heads/$BRANCH"; then
	echo "   Download failed. Nothing was changed." >&2
	exit 1
fi

echo "   Unpacking..."
unzip -q "$stage/source.zip" -d "$stage" || { echo "   The archive would not unpack." >&2; exit 1; }
# GitHub names the folder after the branch, and this branch has a slash in it
# that becomes a dash, so find it rather than spelling it out.
root="$(find "$stage" -mindepth 1 -maxdepth 1 -type d | head -1)"
[ -n "$root" ] || { echo "   The archive was empty." >&2; exit 1; }

echo "   Replacing game files..."
shopt -s dotglob
for item in "$root"/*; do
	name="$(basename "$item")"
	skip=0
	for kept in "${KEEP[@]}"; do
		[ "$name" = "$kept" ] && skip=1
	done
	[ "$skip" = 1 ] && continue
	# Replaced whole rather than merged, so a file deleted upstream is actually
	# gone here: a stale .gd left behind still registers its class_name and can
	# shadow the real one.
	rm -rf "${PROJECT:?}/$name"
	cp -R "$item" "$PROJECT/$name"
done
shopt -u dotglob

write_version "$sha" "$subject"

# Re-import, because a stale cache is the one failure that looks like a broken
# game rather than a broken install: new scripts arrived and old ones left, so
# Godot's global class cache no longer matches what is on disk, and an
# unresolved class_name stops the autoloads compiling. Then the arena renders
# perfectly and no button does anything. Rebuild it, or delete it so the
# launcher rebuilds it -- but never leave it stale.
GODOT_BIN=""
if [ -f "$PROJECT/godot_path.txt" ]; then
	candidate="$(tr -d '\r\n' < "$PROJECT/godot_path.txt")"
	[ -x "$candidate" ] && GODOT_BIN="$candidate"
fi
[ -z "$GODOT_BIN" ] && [ -n "${GODOT:-}" ] && [ -x "${GODOT}" ] && GODOT_BIN="$GODOT"
[ -z "$GODOT_BIN" ] && command -v godot >/dev/null 2>&1 && GODOT_BIN="$(command -v godot)"

if [ -n "$GODOT_BIN" ]; then
	echo "   Re-importing assets..."
	"$GODOT_BIN" --headless --path "$PROJECT" --editor --quit >/dev/null 2>&1
else
	rm -rf "$PROJECT/.godot"
	echo "   Godot was not found, so the asset cache was cleared instead."
	echo "   The next launch will rebuild it (a minute or two, once)."
fi

echo
echo "   Updated to: $subject"
exit 0
