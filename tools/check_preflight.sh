#!/usr/bin/env bash
# Verifies the Windows launcher's guard, which is the one players actually run.
#
# tools/preflight.ps1 decides whether "Play RumbleArena.bat" may start the game.
# It had never been executed by anything but a player: the suite tested the bash
# twin, tools/cache_is_current.sh, and the two drifted -- a fix for a real bug
# went into one and not the other for a whole release.
#
# Skips loudly if no PowerShell is installed. A skipped check is not a passing
# one, and saying so is the difference between "untested here" and "fine".
set -uo pipefail
cd "$(dirname "$0")/.."
PROJECT="$PWD"
PREFLIGHT="$PROJECT/tools/preflight.ps1"

PS=""
for candidate in pwsh powershell /opt/pwsh/pwsh; do
	command -v "$candidate" >/dev/null 2>&1 && { PS="$candidate"; break; }
	[ -x "$candidate" ] && { PS="$candidate"; break; }
done
if [ -z "$PS" ]; then
	echo "Preflight guard: SKIPPED (no PowerShell here; this is the Windows path)."
	exit 0
fi

fail() { echo "FAILED: $1"; exit 1; }

# Returns preflight's exit code. Always with -NoUpdateCheck off in one case, so
# the update notice cannot quietly replace the verdict.
verdict() {
	"$PS" -NoProfile -File "$PREFLIGHT" -ProjectDir "$PROJECT" "$@" >/dev/null 2>&1
	echo $?
}

[ -f "$PREFLIGHT" ] || fail "tools/preflight.ps1 is missing."
[ -s "$PROJECT/.godot/global_script_class_cache.cfg" ] \
	|| fail "no class cache to test against -- run an import pass first."

# 1. A prepared project is ready.
[ "$(verdict -NoUpdateCheck)" = "0" ] || fail "a freshly imported project was reported as stale."

# 2. A class the cache has never heard of is stale. The real failure: a new
#    class_name arrives with an update, the old cache does not know it, and
#    every script referencing it stops compiling.
probe="$PROJECT/src/_preflight_probe.gd"
printf 'class_name PreflightProbe\nextends RefCounted\n' > "$probe"
code="$(verdict -NoUpdateCheck)"
rm -f "$probe"
[ "$code" = "2" ] || fail "a class missing from the cache was NOT detected (got $code)."

# 3. Art that landed after the last import is stale too. This half was measured
#    against the class cache alone, which Godot only rewrites when the class
#    list changes -- so an art-only update looked stale forever and re-imported
#    on every launch.
asset="$PROJECT/assets/_preflight_probe.png"
printf '\211PNG\r\n\032\n' > "$asset"
code="$(verdict -NoUpdateCheck)"
rm -f "$asset"
[ "$code" = "2" ] || fail "art newer than the last import was NOT detected (got $code)."

# 4. Back to ready once the probes are gone, so the check is not simply always
#    stale.
[ "$(verdict -NoUpdateCheck)" = "0" ] || fail "the check stayed stale after the probes were removed."

# 5. The verdict survives the update notice. The launcher calls preflight
#    WITHOUT -NoUpdateCheck, so the update check runs in the same invocation;
#    if that could set the exit code, every launch would read as ready.
probe="$PROJECT/src/_preflight_probe.gd"
printf 'class_name PreflightProbe\nextends RefCounted\n' > "$probe"
code="$(verdict)"
rm -f "$probe"
[ "$code" = "2" ] || fail "the update check replaced the cache verdict (got $code)."

# 6. Art that landed BEFORE the last import is ready, even though it is newer
#    than the class cache. This is the case case 3 cannot see and the one that
#    was actually broken: Godot only rewrites the class cache when the list of
#    classes changes, so after an art-only update every asset is newer than it
#    forever, and the launcher re-imported on every single launch.
asset="$PROJECT/assets/_preflight_probe.png"
printf '\211PNG\r\n\032\n' > "$asset"
touch -d "+2 seconds" "$PROJECT/.godot/uid_cache.bin"
code="$(verdict -NoUpdateCheck)"
rm -f "$asset"
touch "$PROJECT/.godot/uid_cache.bin"
[ "$code" = "0" ] || fail "art older than the last import was called stale (got $code) -- this re-imports on every launch."

# 7. -Explain says which classes are missing, and asking for the explanation
#    does not change the verdict. It did once: a Write-Output inside the check
#    joined the function's return value, and a non-empty array is truthy, so
#    -Explain turned a stale cache into a ready one.
probe="$PROJECT/src/_preflight_probe.gd"
printf 'class_name PreflightProbe\nextends RefCounted\n' > "$probe"
explained="$("$PS" -NoProfile -File "$PREFLIGHT" -ProjectDir "$PROJECT" -NoUpdateCheck -Explain 2>&1)"
code=$?
rm -f "$probe"
[ "$code" = "2" ] || fail "-Explain changed the verdict (got $code)."
grep -q "PreflightProbe" <<<"$explained" \
	|| fail "-Explain did not name the missing class. It said: $explained"

echo "Preflight guard ($PS): stale caches and unimported art refuse to launch;"
echo "  prepared art does not, and -Explain names the missing classes."
