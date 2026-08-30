# Downloads Godot 4.3 for Windows into the project folder.
# Called by Setup.bat, and only after the user has said yes.
param([Parameter(Mandatory = $true)][string]$ProjectDir)

$ErrorActionPreference = 'Stop'
$url = 'https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_win64.exe.zip'
$project = (Resolve-Path $ProjectDir).Path
$zip = Join-Path $project 'godot_download.zip'

Write-Host "  Downloading Godot 4.3 (about 60 MB)..." -ForegroundColor Cyan
try {
	# Some older PowerShell defaults refuse the release CDN without TLS 1.2.
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$ProgressPreference = 'SilentlyContinue'
	Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

	Write-Host "  Unpacking..." -ForegroundColor Cyan
	Expand-Archive -Path $zip -DestinationPath $project -Force
	Remove-Item $zip -Force

	$exe = Get-ChildItem -Path $project -Filter 'Godot*.exe' | Select-Object -First 1
	if ($null -eq $exe) { throw 'The archive did not contain a Godot executable.' }
	Write-Host "  Installed: $($exe.FullName)" -ForegroundColor Green
	exit 0
}
catch {
	Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
	Write-Host "  Download Godot 4.3 by hand from https://godotengine.org/download"
	Write-Host "  and put the .exe in this folder, then run Setup again."
	if (Test-Path $zip) { Remove-Item $zip -Force }
	exit 1
}
