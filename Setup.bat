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
echo     3. Puts a RumbleArena shortcut on your Desktop
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

REM A freshly downloaded copy has no .godot folder, so Godot has not yet
REM imported the assets or built its global class cache. Launching the game
REM without that cache leaves every class_name type unresolved: the autoloads
REM fail to compile and NOTHING responds to input. The editor pass builds it.
if exist "%~dp0.godot\global_script_class_cache.cfg" goto :imported
echo   [2/3] Preparing assets. This takes a minute or two, and only
echo         happens once.
"!GODOT_EXE!" --headless --path "%~dp0." --editor --quit
echo         Done.
echo.
goto :shortcut

:imported
echo   [2/3] Assets already prepared.
echo.

:shortcut
echo   [3/3] Creating the Desktop shortcut...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\create_shortcut.ps1" -ProjectDir "%~dp0."
if errorlevel 1 goto :noshortcut

echo.
echo   Done. There is now a RumbleArena icon on your Desktop.
echo   Press A on a gamepad, or SPACE on the keyboard, to join.
echo.
set "PLAY="
set /p "PLAY=  Launch the game now? [Y/N] "
if /i "!PLAY!"=="Y" start "" "%~dp0Play RumbleArena.bat"
exit /b 0

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
