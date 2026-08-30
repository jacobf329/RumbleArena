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
	[switch]$NoUpdateCheck
)

$project = (Resolve-Path $ProjectDir).Path
$cache = Join-Path $project '.godot\global_script_class_cache.cfg'


## Every class_name the project declares. These are exactly the names the cache
## has to know for the code to compile.
function Get-DeclaredClasses($project) {
	$names = New-Object System.Collections.Generic.HashSet[string]
	$sources = Get-ChildItem -LiteralPath $project -Recurse -Filter '*.gd' -File -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -notlike "*\.godot\*" }
	foreach ($file in $sources) {
		foreach ($line in [IO.File]::ReadLines($file.FullName)) {
			if ($line -match '^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)') {
				[void]$names.Add($Matches[1])
			}
		}
	}
	return $names
}


function Test-CacheIsCurrent($project) {
	if (-not (Test-Path -LiteralPath $cache)) { return $false }
	$text = Get-Content -LiteralPath $cache -Raw -ErrorAction SilentlyContinue
	if ([string]::IsNullOrWhiteSpace($text)) { return $false }

	foreach ($name in (Get-DeclaredClasses $project)) {
		# Quoted, so a class called Fighter is not satisfied by FighterState.
		if ($text -notmatch ('"' + [regex]::Escape($name) + '"')) { return $false }
	}

	# A source newer than the cache means content landed after it was built:
	# imported .glb and .png live in .godot too, and a missing one fails at load
	# rather than at compile.
	#
	# Whitelisted by extension rather than "everything except X". Godot rewrites
	# .import files as part of importing, so anything-newer-than-the-cache is
	# permanently true the moment an import finishes -- a check that can never
	# pass is worse than no check, because it sends the launcher round the same
	# loop every single launch.
	$watched = @('.gd', '.tscn', '.tres', '.gdshader', '.glb', '.gltf',
		'.png', '.jpg', '.svg', '.ogg', '.wav')
	$cacheTime = (Get-Item -LiteralPath $cache).LastWriteTime
	$newest = Get-ChildItem -LiteralPath $project -Recurse -File -ErrorAction SilentlyContinue |
		Where-Object {
			$_.FullName -notlike "*\.godot\*" -and
			($watched -contains $_.Extension -or $_.Name -eq 'project.godot')
		} |
		Sort-Object LastWriteTime -Descending | Select-Object -First 1
	if ($newest -and $newest.LastWriteTime -gt $cacheTime) { return $false }

	return $true
}


$ready = $false
try { $ready = Test-CacheIsCurrent $project }
catch { $ready = $false }   # if the check itself cannot run, re-import: it is only slow

if (-not $NoUpdateCheck) {
	try { & (Join-Path $PSScriptRoot 'update.ps1') -ProjectDir $project -CheckOnly -TimeoutSec 4 } catch { }
}

if ($ready) { exit 0 }
exit 2
