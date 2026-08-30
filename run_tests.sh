#!/usr/bin/env bash
# Headless validation. Set GODOT to your Godot 4.3 binary if it is not on PATH.
#
#   ./run_tests.sh
#
# Runs an import pass that surfaces script and scene parse errors, then every
# test suite. Each drives real fighters through the real main scene with
# scripted input sources.
set -uo pipefail

GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "$0")" && pwd)"

echo "==> Importing project (script and scene parse check)"
import_output="$("$GODOT" --headless --path "$PROJECT" --editor --quit 2>&1)"
echo "$import_output"
if grep -qE "SCRIPT ERROR|Parse Error|Failed loading resource" <<<"$import_output"; then
	echo "FAILED: project did not import cleanly"
	exit 1
fi

status=0
for suite in m1_smoke_test m2_combat_test m3_interaction_test; do
	echo
	echo "==> Running $suite"
	if ! "$GODOT" --headless --path "$PROJECT" "res://tests/$suite.tscn"; then
		status=1
	fi
done
exit "$status"
