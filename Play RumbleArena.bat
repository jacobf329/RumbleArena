@echo off
setlocal enabledelayedexpansion
title RumbleArena
cd /d "%~dp0"

echo.
echo   RumbleArena
echo   -----------
echo.

call "%~dp0tools\find_godot.bat"
if not defined GODOT_EXE goto :missing

REM Godot has to have imported the assets and registered every class_name
REM before the game is launchable: without that cache the autoloads fail to
REM compile and NOTHING responds to input, while the arena still renders
REM perfectly. The test is whether the cache MATCHES the scripts on disk, not
REM merely whether a cache exists -- replacing a game folder by hand leaves the
REM old one behind, and an old cache that has never heard of a new class is
REM exactly as broken as no cache at all. Preflight also prints the update
REM notice, so the launcher pays for only one PowerShell start.
REM If the preflight script itself is missing, this install is mangled; fall
REM back to the old "is there a cache at all" test rather than refusing to run.
if not exist "%~dp0tools\preflight.ps1" goto :legacy_check
if exist "%~dp0no_update_check.txt" goto :preflight_quiet
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preflight.ps1" -ProjectDir "%~dp0."
goto :preflight_done
:preflight_quiet
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preflight.ps1" -ProjectDir "%~dp0." -NoUpdateCheck
:preflight_done
if not errorlevel 2 goto :ready
goto :prepare

:legacy_check
if exist "%~dp0.godot\global_script_class_cache.cfg" goto :ready

:prepare

echo   Preparing assets. This takes a minute or two, and only happens
echo   when the game files have changed.
echo.
"!GODOT_EXE!" --headless --path "%~dp0." --editor --quit > "%~dp0setup_log.txt" 2>&1

REM An import pass that fails still exits 0 and still leaves a .godot folder
REM behind, so "we ran it" is not evidence that it worked. Checking is what
REM turns a game that silently ignores the controller into a message saying why.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preflight.ps1" -ProjectDir "%~dp0." -NoUpdateCheck
if errorlevel 2 goto :notprepared
echo   Ready.
echo.

:ready
set "EXTRA="
if /i "%~1"=="--compat" set "EXTRA=--rendering-driver opengl3 --rendering-method gl_compatibility"

echo   Using: !GODOT_EXE!
if defined EXTRA echo   Compatibility renderer (OpenGL)
echo   Press A on a gamepad, or SPACE on the keyboard, to join.
echo.
"!GODOT_EXE!" --path "%~dp0." !EXTRA!
if errorlevel 1 goto :failed
exit /b 0

:failed
echo.
if defined EXTRA goto :failed_message
echo   Godot exited with an error. If it mentioned Vulkan, your GPU or its
echo   drivers cannot run the default renderer. Try running:
echo       "Play RumbleArena.bat" --compat
echo.

:failed_message
echo   Press any key to close.
pause >nul
exit /b 1

:notprepared
echo.
echo   Preparing the assets did not work, so the game would start with
echo   nothing responding to input. Rather than launch it like that:
echo.
echo     1. Delete the .godot folder in this game folder, then run this again.
echo     2. If that fails too, run Diagnose.bat and send me what it saves.
echo.
echo   The details are in setup_log.txt next to this launcher.
echo.
echo   Press any key to close.
pause >nul
exit /b 1

:missing
echo   Could not find Godot 4.3.
echo.
echo   Easiest fix: close this and run Setup.bat instead. It will fetch
echo   Godot for you and make a Desktop shortcut.
echo.
echo   Press any key to close.
pause >nul
exit /b 1
