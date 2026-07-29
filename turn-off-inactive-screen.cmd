@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "ACTION=%~1"

if "%ACTION%"=="" goto help

if /i "%ACTION%"=="on" goto on
if /i "%ACTION%"=="-on" goto on
if /i "%ACTION%"=="start" goto on
if /i "%ACTION%"=="-start" goto on

if /i "%ACTION%"=="off" goto off
if /i "%ACTION%"=="-off" goto off
if /i "%ACTION%"=="stop" goto off
if /i "%ACTION%"=="-stop" goto off

if /i "%ACTION%"=="now" goto now
if /i "%ACTION%"=="-now" goto now

if /i "%ACTION%"=="status" goto status
if /i "%ACTION%"=="-status" goto status

goto help

:on
call "%SCRIPT_DIR%Start-Inactivity-Monitor.cmd"
echo Inactivity monitor started.
exit /b 0

:off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Stop-Inactivity-Monitor.ps1"
) else (
    pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Stop-Inactivity-Monitor.ps1"
)
exit /b %errorlevel%

:now
call "%SCRIPT_DIR%Turn-Off-Display.cmd"
exit /b 0

:status
set "PID_FILE=%SCRIPT_DIR%state\InactivityMonitor.pid"
if not exist "%PID_FILE%" (
    echo Inactivity monitor stopped.
    exit /b 0
)
set /p MONITOR_PID=<"%PID_FILE%"
tasklist /fi "PID eq %MONITOR_PID%" | findstr /r /c:"^[pP][wW][sS][hH]\.exe" /c:"^[pP][oO][wW][eE][rR][sS][hH][eE][lL][lL]\.exe" >nul
if errorlevel 1 (
    echo Inactivity monitor stopped. Stale PID file: %MONITOR_PID%
) else (
    echo Inactivity monitor running. PID: %MONITOR_PID%
)
exit /b 0

:help
echo Usage:
echo   turn-off-inactive-screen on
echo   turn-off-inactive-screen off
echo   turn-off-inactive-screen now
echo   turn-off-inactive-screen status
exit /b 1
