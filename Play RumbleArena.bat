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
REM Only a clean 0 means ready. Preflight answers 2 for a stale cache, but
REM PowerShell answers 1 for an unhandled error of its own -- and "not
REM errorlevel 2" read that as permission to launch, which is the one thing
REM this check exists to refuse. A guard whose failure mode is "carry on" is
REM not a guard.
if errorlevel 1 goto :prepare
goto :ready

:legacy_check
if exist "%~dp0.godot\global_script_class_cache.cfg" goto :ready

:prepare

echo   Preparing assets. This takes a minute or two, and only happens
echo   when the game files have changed.
echo.
REM Repeated until the cache is actually usable rather than run once and hoped
REM over. Godot quits after a single main-loop iteration, so on a slow disk or a
REM big import it can stop with work still outstanding, leaving a class cache
REM missing whatever had not compiled yet -- which is a game that renders and
REM ignores the controller. An import pass that fails still exits 0 and still
REM leaves a .godot behind, so "we ran it" is never evidence that it worked.
set /a ATTEMPT=0
:prepare_attempt
set /a ATTEMPT+=1
if !ATTEMPT! gtr 1 echo   Still preparing (pass !ATTEMPT!)...
"!GODOT_EXE!" --headless --path "%~dp0." --editor --quit > "%~dp0setup_log.txt" 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\preflight.ps1" -ProjectDir "%~dp0." -NoUpdateCheck
if not errorlevel 1 goto :prepared
if !ATTEMPT! lss 3 goto :prepare_attempt
goto :notprepared

:prepared
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
