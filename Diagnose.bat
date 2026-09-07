@echo off
REM Collects everything I would need to work out why the game will not run,
REM and saves it to one file you can send me. Reads only; changes nothing.
setlocal enabledelayedexpansion
title RumbleArena Diagnostics
cd /d "%~dp0"
set "OUT=%~dp0diagnostics.txt"

echo.
echo   Collecting diagnostics...
echo.

> "%OUT%" echo RumbleArena diagnostics - %DATE% %TIME%
>> "%OUT%" echo Folder: %~dp0
>> "%OUT%" echo.

call "%~dp0tools\find_godot.bat"
>> "%OUT%" echo == Godot ==
if defined GODOT_EXE (
	>> "%OUT%" echo Found: !GODOT_EXE!
	for /f "delims=" %%V in ('"!GODOT_EXE!" --version 2^>^&1') do >> "%OUT%" echo Version: %%V
) else (
	>> "%OUT%" echo Found: NONE - this is the problem.
)
>> "%OUT%" echo.

>> "%OUT%" echo == Asset cache ==
if exist "%~dp0.godot\global_script_class_cache.cfg" (
	>> "%OUT%" echo Cache file: present
	REM Only a clean 0 is "current": PowerShell reports its own errors as 1, and
	REM reading that as healthy is how a broken install looks fine in a report.
	powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preflight.ps1" -ProjectDir "%~dp0." -NoUpdateCheck >nul 2>&1
	if errorlevel 1 (
		>> "%OUT%" echo Cache state: STALE - does not match the scripts on disk.
		REM Which classes, not just that it is stale. This failure has shipped
		REM three times and the missing names point straight at the cause.
		powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preflight.ps1" -ProjectDir "%~dp0." -NoUpdateCheck -Explain >> "%OUT%" 2>&1
	) else (
		>> "%OUT%" echo Cache state: current
	)
) else (
	>> "%OUT%" echo Cache file: MISSING - the assets were never prepared.
)
>> "%OUT%" echo.

>> "%OUT%" echo == Version installed ==
if exist "%~dp0version.json" (type "%~dp0version.json" >> "%OUT%") else (>> "%OUT%" echo version.json: absent)
>> "%OUT%" echo.

>> "%OUT%" echo == Files present ==
for %%F in (project.godot "Play RumbleArena.bat" "Update RumbleArena.bat" Setup.bat) do (
	if exist "%~dp0%%~F" (>> "%OUT%" echo   ok      %%~F) else (>> "%OUT%" echo   MISSING %%~F)
)
for %%D in (src scenes assets tools tests) do (
	if exist "%~dp0%%D\" (>> "%OUT%" echo   ok      %%D\) else (>> "%OUT%" echo   MISSING %%D\)
)
>> "%OUT%" echo.

>> "%OUT%" echo == Last asset-preparation log ==
if exist "%~dp0setup_log.txt" (
	type "%~dp0setup_log.txt" >> "%OUT%"
) else (
	>> "%OUT%" echo setup_log.txt: absent
)
>> "%OUT%" echo.

>> "%OUT%" echo == A fresh run of the game, first 200 lines ==
if defined GODOT_EXE (
	"!GODOT_EXE!" --headless --path "%~dp0." --quit-after 120 > "%~dp0boot_log.txt" 2>&1
	powershell -NoProfile -Command "Get-Content '%~dp0boot_log.txt' -TotalCount 200" >> "%OUT%" 2>nul
)
>> "%OUT%" echo.

echo   Saved to:
echo     %OUT%
echo.
echo   Send me that file and I can tell you exactly what went wrong.
echo.
echo   Press any key to close.
pause >nul
exit /b 0
