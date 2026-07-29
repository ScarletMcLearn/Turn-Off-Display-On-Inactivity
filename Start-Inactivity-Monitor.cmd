@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%Monitor-Inactivity.ps1"

where pwsh.exe >nul 2>nul
if errorlevel 1 (
    set "PS_EXE=powershell.exe"
) else (
    set "PS_EXE=pwsh.exe"
)

start "" /min "%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT_PATH%"

endlocal
exit /b 0
