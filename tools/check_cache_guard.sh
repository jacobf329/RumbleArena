#!/usr/bin/env bash
# Verifies the launchers' staleness check actually catches a stale class cache.
#
# This is the guard on the bug that shipped twice. A cache only means "the
# assets are prepared" if it matches the scripts on disk; the launchers used to
# test whether a cache merely EXISTED, so replacing a game folder by hand left
# the old cache in place and the game started with every autoload dead. The
# arena still rendered, so it looked like a game that ignored the controller.
#
# Cheap enough to run on every test pass, because the failure it guards is
# invisible to every other test: the suite's first step is an import, which
# makes the cache current before anything can notice it was not.
set -uo pipefail
cd "$(dirname "$0")/.."
PROJECT="$PWD"
CHECK="$PROJECT/tools/cache_is_current.sh"
CACHE="$PROJECT/.godot/global_script_class_cache.cfg"

fail() { echo "FAILED: $1"; exit 1; }

[ -x "$CHECK" ] || fail "tools/cache_is_current.sh is missing or not executable."
[ -s "$CACHE" ] || fail "no class cache to test against -- run an import pass first."

# 1. A current cache reads as current.
"$CHECK" "$PROJECT" || fail "a freshly imported project was reported as stale."

# 2. A class the cache has never heard of reads as stale. This is the exact
#    shape of the real failure: a new class_name arrives with an update, the old
#    cache does not know it, and every script referencing it stops compiling.
probe="$PROJECT/src/_cache_guard_probe.gd"
printf 'class_name CacheGuardProbe\nextends RefCounted\n' > "$probe"
if "$CHECK" "$PROJECT"; then
	rm -f "$probe"
	fail "a class missing from the cache was NOT detected -- this is the bug."
fi
rm -f "$probe"

# 3. Removing it puts things back, so the check is not simply always stale.
#    (Touching nothing else: the probe's own mtime is gone with it.)
"$CHECK" "$PROJECT" || fail "the check stayed stale after the probe was removed."

echo "Cache guard: catches a stale class cache."
