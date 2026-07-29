#Requires -Version 5.1
<#
Stops only the inactivity monitor started from this project directory.

Uses the monitor PID file, then verifies the target process command line includes
this project's Monitor-Inactivity.ps1 path before stopping it. This avoids
terminating unrelated PowerShell processes.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MonitorScript = Join-Path -Path $PSScriptRoot -ChildPath 'Monitor-Inactivity.ps1'
$StateDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'state'
$LogDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$PidFile = Join-Path -Path $StateDirectory -ChildPath 'InactivityMonitor.pid'
$LogFile = Join-Path -Path $LogDirectory -ChildPath 'InactivityMonitor.log'

function Write-StopLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz'
        Add-Content -LiteralPath $LogFile -Value "$timestamp [$Level] $Message" -Encoding utf8
    }
    catch {
    }
}

try {
    if (-not (Test-Path -LiteralPath $PidFile -PathType Leaf)) {
        Write-Output 'Inactivity monitor is not running. PID file not found.'
        exit 0
    }

    $pidText = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    $parsedPid = 0
    if (-not [int]::TryParse($pidText, [ref]$parsedPid)) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        throw "Invalid PID file content: $PidFile"
    }

    $monitorPid = $parsedPid
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $monitorPid" -ErrorAction Stop

    if ($null -eq $process) {
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        Write-Output 'Inactivity monitor is not running. Removed stale PID file.'
        exit 0
    }

    $commandLine = [string]$process.CommandLine
    $expectedPath = [System.IO.Path]::GetFullPath($MonitorScript)

    if ($commandLine -notlike "*$expectedPath*") {
        Write-StopLog "Refused to stop PID $monitorPid because command line did not match $expectedPath." 'WARN'
        throw "Refused to stop PID $monitorPid. It does not appear to be this project's inactivity monitor."
    }

    Stop-Process -Id $monitorPid -ErrorAction Stop
    Write-StopLog "Stop requested for monitor PID $monitorPid."
    Write-Output "Stopped inactivity monitor PID $monitorPid."
}
catch {
    Write-StopLog "Error occurred while stopping monitor: $($_.Exception.Message)" 'ERROR'
    throw
}
