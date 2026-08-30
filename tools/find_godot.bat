@echo off
REM Locates a Godot executable and returns it in GODOT_EXE.
REM Shared by "Play RumbleArena.bat" and Setup.bat so the search lives in one
REM place. The final "endlocal & set" exports the result to the caller.
setlocal enabledelayedexpansion
set "FOUND="

REM 1. A path written into godot_path.txt in the project folder wins.
if not exist "%~dp0..\godot_path.txt" goto :try_env
set /p FOUND=<"%~dp0..\godot_path.txt"
if defined FOUND if not exist "!FOUND!" set "FOUND="
if defined FOUND goto :done

:try_env
if not defined GODOT goto :try_path
if exist "%GODOT%" set "FOUND=%GODOT%"
if defined FOUND goto :done

:try_path
for /f "delims=" %%G in ('where godot 2^>nul') do if not defined FOUND set "FOUND=%%G"
if defined FOUND goto :done

REM 2. A Godot executable sitting in the project folder.
for %%G in ("%~dp0..\Godot*.exe") do if not defined FOUND set "FOUND=%%~fG"
if defined FOUND goto :done

REM 3. The usual install and download locations.
call :scan "%LOCALAPPDATA%\Programs\Godot"
if defined FOUND goto :done
call :scan "%ProgramFiles%\Godot"
if defined FOUND goto :done
call :scan "%USERPROFILE%\Downloads"
if defined FOUND goto :done
call :scan "%USERPROFILE%\Desktop"
goto :done

:scan
if not exist "%~1" exit /b 0
for /f "delims=" %%G in ('dir /b /s "%~1\Godot*.exe" 2^>nul') do if not defined FOUND set "FOUND=%%G"
exit /b 0

:done
endlocal & set "GODOT_EXE=%FOUND%"
exit /b 0
