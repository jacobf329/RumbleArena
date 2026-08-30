@echo off
setlocal enabledelayedexpansion
title RumbleArena
cd /d "%~dp0"

echo.
echo   RumbleArena
echo   -----------
echo.

set "GODOT_EXE="

REM 1. A path written into godot_path.txt next to this script wins.
if exist "%~dp0godot_path.txt" (
  set /p GODOT_EXE=<"%~dp0godot_path.txt"
  if not exist "!GODOT_EXE!" set "GODOT_EXE="
)

REM 2. The GODOT environment variable.
if not defined GODOT_EXE if defined GODOT if exist "%GODOT%" set "GODOT_EXE=%GODOT%"

REM 3. Anything named godot on PATH.
if not defined GODOT_EXE (
  for /f "delims=" %%G in ('where godot 2^>nul') do (
    if not defined GODOT_EXE set "GODOT_EXE=%%G"
  )
)

REM 4. A Godot executable sitting beside this script.
if not defined GODOT_EXE (
  for %%G in ("%~dp0Godot*.exe") do (
    if not defined GODOT_EXE set "GODOT_EXE=%%~fG"
  )
)

REM 5. The usual install and download locations.
if not defined GODOT_EXE (
  for %%D in (
    "%LOCALAPPDATA%\Programs\Godot"
    "%ProgramFiles%\Godot"
    "%ProgramFiles(x86)%\Godot"
    "%USERPROFILE%\Downloads"
    "%USERPROFILE%\Desktop"
  ) do (
    if not defined GODOT_EXE (
      for /f "delims=" %%G in ('dir /b /s "%%~D\Godot*.exe" 2^>nul') do (
        if not defined GODOT_EXE set "GODOT_EXE=%%G"
      )
    )
  )
)

if not defined GODOT_EXE goto :missing

set "EXTRA="
if /i "%~1"=="--compat" set "EXTRA=--rendering-driver opengl3 --rendering-method gl_compatibility"

echo   Using: !GODOT_EXE!
if defined EXTRA echo   Compatibility renderer ^(OpenGL^)
echo   Press A on a gamepad, or SPACE on the keyboard, to join.
echo.
"!GODOT_EXE!" --path "%~dp0." !EXTRA!
if errorlevel 1 (
  echo.
  if not defined EXTRA (
    echo   Godot exited with an error. If it mentioned Vulkan, your GPU or its
    echo   drivers cannot run the default renderer. Run this instead:
    echo       "Play RumbleArena.bat" --compat
    echo.
  )
  echo   Press any key to close.
  pause ^>nul
)
exit /b 0

:missing
echo   Could not find Godot 4.3.
echo.
echo   Download it from https://godotengine.org/download  (Godot 4.3, standard
echo   version -- not .NET), then do ONE of these:
echo.
echo     * Drop Godot_v4.3-stable_win64.exe into this folder, or
echo     * Create a file called godot_path.txt in this folder whose only line
echo       is the full path to your Godot .exe
echo.
echo   Press any key to close.
pause >nul
exit /b 1
