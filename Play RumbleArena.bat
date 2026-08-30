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

:missing
echo   Could not find Godot 4.3.
echo.
echo   Easiest fix: close this and run Setup.bat instead. It will fetch
echo   Godot for you and make a Desktop shortcut.
echo.
echo   Press any key to close.
pause >nul
exit /b 1
