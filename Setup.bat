@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title RumbleArena Setup

echo.
echo   ==================================
echo     RumbleArena - first-time setup
echo   ==================================
echo.
echo   This does two things:
echo     1. Makes sure Godot 4.3 is on this PC
echo     2. Prepares the game's assets (first run only)
echo     3. Puts RumbleArena and its updater on your Desktop
echo.

call "%~dp0tools\find_godot.bat"
if defined GODOT_EXE goto :have_godot

echo   [1/3] Godot 4.3 is not on this PC yet.
echo.
echo         I can download it from the official Godot releases page
echo         - about 60 MB - and put it in this folder. Nothing gets
echo         installed and nothing else on your PC is touched.
echo.
set "ANSWER="
set /p "ANSWER=        Download Godot 4.3 now? [Y/N] "
echo.
if /i not "!ANSWER!"=="Y" goto :nogodot

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\download_godot.ps1" -ProjectDir "%~dp0."
call "%~dp0tools\find_godot.bat"
if not defined GODOT_EXE goto :nogodot
goto :have_godot

:have_godot
echo   [1/3] Godot is ready:
echo         !GODOT_EXE!
echo.

REM The cache has to MATCH the scripts on disk, not merely exist. Replacing a
REM game folder by hand leaves the old cache behind, and an old cache that has
REM never heard of a class the new code references makes every script touching
REM it fail to compile -- autoloads included, so nothing responds to input while
REM the arena still renders. "Assets already prepared" was a lie in exactly that
REM case, and it is the reason a correctly-installed game looked dead.
if not exist "%~dp0tools\preflight.ps1" goto :prepare
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preflight.ps1" -ProjectDir "%~dp0." -NoUpdateCheck
if not errorlevel 2 goto :imported

:prepare
echo   [2/3] Preparing assets. This takes a minute or two, and only
echo         happens when the game files have changed.
"!GODOT_EXE!" --headless --path "%~dp0." --editor --quit > "%~dp0setup_log.txt" 2>&1

REM An import pass that fails still exits 0 and still leaves a .godot folder
REM behind, so "we ran it" is not evidence that it worked.
if not exist "%~dp0tools\preflight.ps1" goto :prepared
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preflight.ps1" -ProjectDir "%~dp0." -NoUpdateCheck
if errorlevel 2 goto :notprepared

:prepared
echo         Done.
echo.
goto :shortcut

:imported
echo   [2/3] Assets already prepared and up to date.
echo.

:shortcut
echo   [3/3] Creating the Desktop shortcut...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\create_shortcut.ps1" -ProjectDir "%~dp0."
if errorlevel 1 goto :noshortcut

REM Note which version this is, so the launcher can tell you when there is a
REM newer one. Best effort -- an offline setup just stays quiet about updates.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update.ps1" -ProjectDir "%~dp0." -RecordOnly >nul 2>&1

echo.
echo   Done. There is now a RumbleArena icon on your Desktop, and an
echo   "Update RumbleArena" icon next to it.
echo   Press A on a gamepad, or SPACE on the keyboard, to join.
echo.
echo   When there is a newer version, the launcher will say so. Click the
echo   Update icon to get it - it keeps your Godot download and your
echo   shortcuts, and only replaces the game.
echo.
set "PLAY="
set /p "PLAY=  Launch the game now? [Y/N] "
if /i "!PLAY!"=="Y" start "" "%~dp0Play RumbleArena.bat"
exit /b 0

:notprepared
echo.
echo   Setup stopped: preparing the assets did not work.
echo.
echo   Launching now would give you a game where nothing responds to the
echo   controller, so it is better to stop here. Try this:
echo.
echo     1. Delete the .godot folder in this game folder and run Setup again.
echo     2. If that fails too, run Diagnose.bat and send me what it saves.
echo.
echo   The details are in setup_log.txt next to this file.
echo.
echo   Press any key to close.
pause >nul
exit /b 1

:nogodot
echo.
echo   Setup stopped: there is no Godot 4.3 to run the game with.
echo.
echo   Download it yourself from https://godotengine.org/download
echo   - Godot 4.3, the standard version, NOT the .NET one - then put
echo   the .exe in this folder and run Setup again.
echo.
echo   Press any key to close.
pause >nul
exit /b 1

:noshortcut
echo.
echo   Godot is ready, but the Desktop shortcut could not be created.
echo   You can still play by double-clicking "Play RumbleArena.bat"
echo   in this folder.
echo.
echo   Press any key to close.
pause >nul
exit /b 1
