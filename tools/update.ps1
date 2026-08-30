# Updates an installed RumbleArena to the latest published version.
#
# Run it through "Update RumbleArena.bat" rather than directly: that stages a
# copy of this script in the temp folder first, so the update is free to replace
# every file in the install including the launcher that started it.
param(
	[Parameter(Mandatory = $true)][string]$ProjectDir,
	# Re-download even when the local copy is already current.
	[switch]$Force,
	# Report whether an update exists and exit. Used by the play launcher.
	[switch]$CheckOnly,
	# Write down what is current without downloading anything. Setup uses this
	# so a freshly downloaded copy knows its own version and the launcher's
	# check has something to compare against.
	[switch]$RecordOnly,
	# Seconds to wait on GitHub. Short for the launcher's check, which must not
	# stand between somebody and their game.
	[int]$TimeoutSec = 20
)

$ErrorActionPreference = 'Stop'

$Owner = 'jacobf329'
$Repo = 'RumbleArena'
$Branch = 'claude/godot-ninja-game-96kjrj'

# Everything the repository does not own, and so must survive an update: the
# 60 MB engine, the pointer to wherever it lives, the imported-asset cache, and
# the two files the updater itself keeps state in.
$Keep = @('.godot', 'godot_path.txt', 'version.json', 'no_update_check.txt')

$Api = "https://api.github.com/repos/$Owner/$Repo"
$Headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'RumbleArena-Updater' }


function Get-RemoteHead {
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$commit = Invoke-RestMethod -Uri "$Api/commits/$Branch" -Headers $Headers -TimeoutSec $TimeoutSec
	return [pscustomobject]@{
		sha     = $commit.sha
		subject = ($commit.commit.message -split "`n")[0]
		date    = $commit.commit.author.date
	}
}


function Get-LocalVersion($project) {
	$path = Join-Path $project 'version.json'
	if (-not (Test-Path -LiteralPath $path)) { return $null }
	try { $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
	# A half-written or hand-edited file should read as "no version known",
	# not blow up the updater on a Substring later.
	if (-not $record.sha -or $record.sha.Length -lt 7) { return $null }
	return $record
}


function Save-LocalVersion($project, $head) {
	$record = [pscustomobject]@{
		sha       = $head.sha
		subject   = $head.subject
		committed = $head.date
		updated   = (Get-Date).ToString('s')
		branch    = $Branch
	}
	$record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project 'version.json') -Encoding UTF8
}


## The commit subjects between what is installed and what is about to be, so an
## update says what it is bringing rather than just "done".
function Get-Changes($from, $to) {
	if (-not $from) { return @() }
	try {
		$compare = Invoke-RestMethod -Uri "$Api/compare/$from...$to" -Headers $Headers -TimeoutSec 20
		return @($compare.commits | ForEach-Object { ($_.commit.message -split "`n")[0] })
	}
	catch { return @() }
}


## Godot, if this machine has it where the launcher would look. Only used to
## re-import after an update.
function Find-Godot($project) {
	$pointer = Join-Path $project 'godot_path.txt'
	if (Test-Path -LiteralPath $pointer) {
		$path = (Get-Content -LiteralPath $pointer -Raw).Trim()
		if ($path -and (Test-Path -LiteralPath $path)) { return $path }
	}
	if ($env:GODOT -and (Test-Path -LiteralPath $env:GODOT)) { return $env:GODOT }
	$local = Get-ChildItem -LiteralPath $project -Filter 'Godot*.exe' -ErrorAction SilentlyContinue |
		Select-Object -First 1
	if ($local) { return $local.FullName }
	$onPath = Get-Command godot -ErrorAction SilentlyContinue
	if ($onPath) { return $onPath.Source }
	return $null
}


$project = (Resolve-Path $ProjectDir).Path
$local = Get-LocalVersion $project

# --- Record-only: note what is current, download nothing ---

if ($RecordOnly) {
	try {
		$head = Get-RemoteHead
		Save-LocalVersion $project $head
	}
	catch { }   # best effort; without it the launcher simply says nothing
	exit 0
}

# --- Check-only: one line if there is news, silence otherwise ---

if ($CheckOnly) {
	try { $head = Get-RemoteHead } catch { exit 0 }   # offline is not an error here
	if ($local -and $local.sha -eq $head.sha) { exit 0 }
	if (-not $local) { exit 0 }                        # nothing to compare against yet
	Write-Host ""
	Write-Host "   An update is available: $($head.subject)" -ForegroundColor Yellow
	Write-Host "   Close the game and run 'Update RumbleArena.bat' to get it." -ForegroundColor Yellow
	exit 0
}

Write-Host ""
Write-Host "   =============================" -ForegroundColor Cyan
Write-Host "     RumbleArena - update" -ForegroundColor Cyan
Write-Host "   =============================" -ForegroundColor Cyan
Write-Host ""

# --- A clone updates with git; only a downloaded zip is ours to overwrite ---

if (Test-Path -LiteralPath (Join-Path $project '.git')) {
	Write-Host "   This copy is a git clone, so git owns it." -ForegroundColor Yellow
	Write-Host "   Update it with:"
	Write-Host ""
	Write-Host "       git -C `"$project`" pull"
	Write-Host ""
	Write-Host "   Overwriting a clone's files from a zip would strip its history"
	Write-Host "   and throw away anything you had changed, so this stops here."
	exit 1
}

try { $head = Get-RemoteHead }
catch {
	Write-Host "   Could not reach GitHub: $($_.Exception.Message)" -ForegroundColor Red
	Write-Host "   Check your connection and try again. Nothing was changed."
	exit 1
}

if ($local) {
	Write-Host "   Installed: $($local.subject)"
	Write-Host "              $($local.sha.Substring(0,7))  $($local.committed)"
}
else {
	Write-Host "   Installed: unknown (this copy predates the updater)"
}
Write-Host "   Latest:    $($head.subject)"
Write-Host "              $($head.sha.Substring(0,7))  $($head.date)"
Write-Host ""

if ($local -and $local.sha -eq $head.sha -and -not $Force) {
	Write-Host "   Already up to date." -ForegroundColor Green
	exit 0
}

$changes = @(Get-Changes $(if ($local) { $local.sha } else { $null }) $head.sha)
if ($changes.Count -gt 0) {
	Write-Host "   What you are getting:" -ForegroundColor Cyan
	foreach ($line in ($changes | Select-Object -Last 12)) { Write-Host "     - $line" }
	Write-Host ""
}

# --- Download and swap ---

$stage = Join-Path $env:TEMP ("RumbleArena-update-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$zip = Join-Path $stage 'source.zip'

try {
	Write-Host "   Downloading (about 20 MB)..." -ForegroundColor Cyan
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$ProgressPreference = 'SilentlyContinue'
	Invoke-WebRequest -Uri "https://codeload.github.com/$Owner/$Repo/zip/refs/heads/$Branch" `
		-OutFile $zip -UseBasicParsing -TimeoutSec 300

	Write-Host "   Unpacking..." -ForegroundColor Cyan
	Expand-Archive -Path $zip -DestinationPath $stage -Force
	# GitHub names the folder after the branch, and the branch has a slash in it
	# that becomes a dash, so find it rather than spelling it out.
	$root = Get-ChildItem -LiteralPath $stage -Directory | Select-Object -First 1
	if ($null -eq $root) { throw 'The archive was empty.' }

	Write-Host "   Replacing game files..." -ForegroundColor Cyan
	foreach ($item in Get-ChildItem -LiteralPath $root.FullName -Force) {
		if ($Keep -contains $item.Name) { continue }
		$destination = Join-Path $project $item.Name
		# Replaced whole rather than merged, so a file deleted upstream is
		# actually gone here: a stale .gd left behind still registers its
		# class_name and can shadow the real one.
		if (Test-Path -LiteralPath $destination) {
			Remove-Item -LiteralPath $destination -Recurse -Force
		}
		Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
	}

	Save-LocalVersion $project $head
}
catch {
	Write-Host ""
	Write-Host "   Update failed: $($_.Exception.Message)" -ForegroundColor Red
	Write-Host "   Your existing copy may be half-replaced. The safe fix is to"
	Write-Host "   download the game fresh and run Setup.bat again."
	if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
	exit 1
}
finally {
	if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- Re-import, because a stale cache is the one failure that looks like a
# --- broken game rather than a broken install ---
#
# New scripts arrived and old ones left, so Godot's global class cache no longer
# matches what is on disk. An unresolved class_name stops the autoloads from
# compiling, and then the arena renders perfectly while no button does anything.
# Either rebuild the cache now, or delete it so the launcher rebuilds it -- but
# never leave it stale.

$godot = Find-Godot $project
if ($godot) {
	Write-Host "   Re-importing assets..." -ForegroundColor Cyan
	& $godot --headless --path $project --editor --quit | Out-Null
}
else {
	$cache = Join-Path $project '.godot'
	if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force }
	Write-Host "   Godot was not found, so the asset cache was cleared instead."
	Write-Host "   The next launch will rebuild it (a minute or two, once)."
}

Write-Host ""
Write-Host "   Updated to: $($head.subject)" -ForegroundColor Green
Write-Host "   Your Desktop shortcut still works - just launch as usual." -ForegroundColor Green
exit 0
