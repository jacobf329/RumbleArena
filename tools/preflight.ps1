# Decides whether the asset cache needs rebuilding, and mentions updates.
#
# Exit codes:  0 = ready to play    2 = the cache is stale, re-import first
#
# "Does .godot exist" was the old test, and it is wrong: a cache only means the
# assets are prepared if it matches the scripts actually on disk. Replacing a
# game folder by hand leaves the old cache in place, and a cache that has never
# heard of a class the code now references makes every script that touches it
# fail to compile -- autoloads included, so nothing responds to input while the
# arena still renders perfectly. That is not a state a launcher should start.
param(
	[Parameter(Mandatory = $true)][string]$ProjectDir,
	# Skip the update notice (Setup does its own thing about versions).
	[switch]$NoUpdateCheck,
	# Say *why* the cache is stale rather than only that it is. Diagnose uses
	# this: "the cache is stale" has never once been enough to work from, and
	# the names of the classes it is missing point straight at the script that
	# failed to compile.
	[switch]$Explain
)

$project = (Resolve-Path $ProjectDir).Path
$godotDir = Join-Path $project '.godot'
$cache = Join-Path $godotDir 'global_script_class_cache.cfg'
# Rewritten by any import, unlike the class cache. See Test-CacheIsCurrent.
$uidCache = Join-Path $godotDir 'uid_cache.bin'


## True if the path has a .godot segment. Written against both separators so
## this script can be run, and therefore tested, off Windows.
function Test-InGodotDir($path) {
	return ($path -split '[\\/]') -contains '.godot'
}


## Every class_name the project declares. These are exactly the names the cache
## has to know for the code to compile.
function Get-DeclaredClasses($project) {
	$names = New-Object System.Collections.Generic.HashSet[string]
	$sources = Get-ChildItem -LiteralPath $project -Recurse -Filter '*.gd' -File -ErrorAction SilentlyContinue |
		Where-Object { -not (Test-InGodotDir $_.FullName) }
	foreach ($file in $sources) {
		foreach ($line in [IO.File]::ReadLines($file.FullName)) {
			if ($line -match '^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)') {
				[void]$names.Add($Matches[1])
			}
		}
	}
	return $names
}


## Why the cache was rejected, collected rather than printed.
##
## Printing from inside Test-CacheIsCurrent looks harmless and is not: a
## PowerShell function returns *everything* written to the output stream, so a
## Write-Output there makes the function return @("some text", $false) -- and a
## non-empty array is truthy, so the caller reads a stale cache as ready. Which
## is the fail-open shape this whole file exists to avoid, arrived at from the
## inside. Collected here, printed by the caller once the verdict is decided.
$script:Reasons = @()


function Test-CacheIsCurrent($project) {
	if (-not (Test-Path -LiteralPath $cache)) {
		$script:Reasons += "There is no class cache at all: the assets were never prepared."
		return $false
	}
	$text = Get-Content -LiteralPath $cache -Raw -ErrorAction SilentlyContinue
	if ([string]::IsNullOrWhiteSpace($text)) {
		$script:Reasons += "The class cache is empty."
		return $false
	}

	$missing = @()
	foreach ($name in (Get-DeclaredClasses $project)) {
		# Quoted, so a class called Fighter is not satisfied by FighterState.
		if ($text -notmatch ('"' + [regex]::Escape($name) + '"')) { $missing += $name }
	}
	if ($missing.Count -gt 0) {
		$script:Reasons += ("Classes the cache is missing ({0}): {1}" -f `
			$missing.Count, (($missing | Sort-Object) -join ', '))
		$script:Reasons += "One of those names the script that failed to compile."
		return $false
	}

	# A source newer than the last import means content landed after it was
	# prepared: imported .glb and .png live in .godot too, and a missing one
	# fails at load rather than at compile.
	#
	# Measured against the most recent sign of an import, not the class cache
	# alone. Godot only rewrites global_script_class_cache.cfg when the list of
	# classes changes, so an update that adds art and no new class_name leaves
	# that file with an old timestamp, every new .png looks like it landed
	# afterwards, and the launcher re-imports on every single launch forever.
	# The uid cache is rewritten by any import, so the newer of the two is what
	# "the assets were last prepared" actually means.
	$reference = (Get-Item -LiteralPath $cache).LastWriteTime
	if (Test-Path -LiteralPath $uidCache) {
		$uidTime = (Get-Item -LiteralPath $uidCache).LastWriteTime
		if ($uidTime -gt $reference) { $reference = $uidTime }
	}

	# Whitelisted by extension rather than "everything except X". Godot rewrites
	# .import files as part of importing, so anything-newer-than-the-reference
	# is permanently true the moment an import finishes -- a check that can
	# never pass is worse than no check, because it sends the launcher round the
	# same loop every single launch.
	$watched = @('.gd', '.tscn', '.tres', '.gdshader', '.glb', '.gltf',
		'.png', '.jpg', '.svg', '.ogg', '.wav')
	$newest = Get-ChildItem -LiteralPath $project -Recurse -File -ErrorAction SilentlyContinue |
		Where-Object {
			-not (Test-InGodotDir $_.FullName) -and
			($watched -contains $_.Extension -or $_.Name -eq 'project.godot')
		} |
		Sort-Object LastWriteTime -Descending | Select-Object -First 1
	if ($newest -and $newest.LastWriteTime -gt $reference) {
		$script:Reasons += ("Changed after the last asset pass: {0} ({1:yyyy-MM-dd HH:mm:ss}, prepared {2:yyyy-MM-dd HH:mm:ss})" -f `
			$newest.Name, $newest.LastWriteTime, $reference)
		return $false
	}

	return $true
}


$ready = $false
# [bool] on purpose: a function that leaked anything to the output stream would
# otherwise hand back an array, and a non-empty array is truthy.
try { $ready = [bool](Test-CacheIsCurrent $project) }
catch {
	$ready = $false   # if the check itself cannot run, re-import: it is only slow
	$script:Reasons += ("The check itself failed: {0}" -f $_.Exception.Message)
}

if ($Explain -and -not $ready) {
	foreach ($reason in $script:Reasons) { Write-Output $reason }
}

# Anything that goes wrong from here on must still leave a usable exit code, and
# the callers read "not 0" as "not ready" -- so an unhandled error, which
# PowerShell reports as 1, means re-import rather than launch. A guard whose
# failure mode is "carry on" is not a guard.

if (-not $NoUpdateCheck) {
	try { & (Join-Path $PSScriptRoot 'update.ps1') -ProjectDir $project -CheckOnly -TimeoutSec 4 } catch { }
}

if ($ready) { exit 0 }
exit 2
