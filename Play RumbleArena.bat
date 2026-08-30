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

REM A freshly downloaded copy has no .godot folder, so Godot has not yet
REM imported the assets or built its global class cache. Launching the game
REM without that cache leaves every class_name type unresolved: the autoloads
REM fail to compile and NOTHING responds to input. The editor pass builds it.
if exist "%~dp0.godot\global_script_class_cache.cfg" goto :ready
echo   First run: preparing assets. This takes a minute or two,
echo   and only happens once.
echo.
"!GODOT_EXE!" --headless --path "%~dp0." --editor --quit
echo   Ready.
echo.

:ready
set "EXTRA="
if /i "%~1"=="--compat" set "EXTRA=--rendering-driver opengl3 --rendering-method gl_compatibility"

REM One line if there is a newer version, nothing otherwise. Bounded to a few
REM seconds and never fatal: being offline must not stand between somebody and
REM their game. Drop a file called no_update_check.txt in this folder to skip it.
if exist "%~dp0no_update_check.txt" goto :nocheck
if not exist "%~dp0tools\check_update.ps1" goto :nocheck
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\check_update.ps1" -ProjectDir "%~dp0." 2>nul

:nocheck
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

:missing
echo   Could not find Godot 4.3.
echo.
echo   Easiest fix: close this and run Setup.bat instead. It will fetch
echo   Godot for you and make a Desktop shortcut.
echo.
echo   Press any key to close.
pause >nul
exit /b 1
