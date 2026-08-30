# Creates a RumbleArena shortcut on the current user's Desktop.
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
$target = Join-Path $desktop 'RumbleArena.lnk'

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($target)
$link.TargetPath = $launcher
$link.WorkingDirectory = $project
$link.Description = 'RumbleArena - 4-player ninja arena brawler'

$icon = Join-Path $project 'icon.ico'
if (Test-Path $icon) { $link.IconLocation = $icon }

$link.Save()
Write-Host "Created: $target" -ForegroundColor Green
