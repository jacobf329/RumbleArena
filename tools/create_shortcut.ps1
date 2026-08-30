# Creates the RumbleArena shortcuts on the current user's Desktop: one to play,
# one to update. The updater gets its own icon because a notice you have to go
# hunting through a folder to act on is a notice most people ignore.
# Called by "Create Desktop Shortcut.bat"; not usually run directly.
param([Parameter(Mandatory = $true)][string]$ProjectDir)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path $ProjectDir).Path
$launcher = Join-Path $project 'Play RumbleArena.bat'

if (-not (Test-Path $launcher)) {
	Write-Host "Could not find '$launcher'." -ForegroundColor Red
	Write-Host "Run this from inside the RumbleArena project folder."
	exit 1
}

$desktop = [Environment]::GetFolderPath('Desktop')
$icon = Join-Path $project 'icon.ico'
$shell = New-Object -ComObject WScript.Shell

function New-Link($name, $targetPath, $description) {
	if (-not (Test-Path $targetPath)) { return }
	$path = Join-Path $desktop $name
	$link = $shell.CreateShortcut($path)
	$link.TargetPath = $targetPath
	$link.WorkingDirectory = $project
	$link.Description = $description
	if (Test-Path $icon) { $link.IconLocation = $icon }
	$link.Save()
	Write-Host "Created: $path" -ForegroundColor Green
}

New-Link 'RumbleArena.lnk' $launcher 'RumbleArena - 4-player ninja arena brawler'
New-Link 'Update RumbleArena.lnk' (Join-Path $project 'Update RumbleArena.bat') `
	'Download the latest version of RumbleArena' 
