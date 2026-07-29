#Requires -Version 5.1
<#
Monitors real Windows keyboard/mouse inactivity and turns off displays after the
configured timeout. This script keeps running until stopped.

It never locks Windows, starts the screen saver, sleeps, hibernates, signs out,
shuts down, or simulates user input. Display power-off is delegated to
Turn-Off-Display.ps1 in this same directory.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Change this value to adjust the inactivity threshold.
$IdleTimeoutSeconds = 60

# Polling every 1-2 seconds is responsive without busy looping.
$PollIntervalSeconds = 1

$ProjectName = 'WindowsDisplayOffInactivityMonitor'
$DisplayOffScript = Join-Path -Path $PSScriptRoot -ChildPath 'Turn-Off-Display.ps1'
$StateDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'state'
$LogDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$PidFile = Join-Path -Path $StateDirectory -ChildPath 'InactivityMonitor.pid'
$LogFile = Join-Path -Path $LogDirectory -ChildPath 'InactivityMonitor.log'
$MaxLogBytes = 1MB
$DisplayTurnedOffForCurrentIdlePeriod = $false
$mutex = $null
$ownsMutex = $false
$CurrentProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id

function Get-StableNameHash {
    param([Parameter(Mandatory)][string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text.ToUpperInvariant())
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($bytes)
        $hex = ($hashBytes | ForEach-Object { $_.ToString('x2') }) -join ''
        return $hex.Substring(0, 16)
    }
    finally {
        $sha256.Dispose()
    }
}

function Initialize-Directories {
    New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
}

function Write-MonitorLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        if (Test-Path -LiteralPath $LogFile) {
            $length = (Get-Item -LiteralPath $LogFile).Length
            if ($length -gt $MaxLogBytes) {
                $oldLog = "$LogFile.old"
                Remove-Item -LiteralPath $oldLog -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $LogFile -Destination $oldLog -Force
            }
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz'
        Add-Content -LiteralPath $LogFile -Value "$timestamp [$Level] $Message" -Encoding utf8
    }
    catch {
        # Logging must never keep the monitor from doing its main job.
    }
}

function Add-IdleNativeType {
    if ('DisplayOffIdle.NativeMethods' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace DisplayOffIdle
{
    public static class NativeMethods
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LASTINPUTINFO
        {
            public uint cbSize;
            public uint dwTime;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

        [DllImport("kernel32.dll")]
        private static extern uint GetTickCount();

        public static uint GetIdleMilliseconds()
        {
            LASTINPUTINFO lastInput = new LASTINPUTINFO();
            lastInput.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));

            if (!GetLastInputInfo(ref lastInput))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetLastInputInfo failed.");
            }

            uint now = GetTickCount();
            return unchecked(now - lastInput.dwTime);
        }
    }
}
'@
}

function Get-IdleTimeSeconds {
    Add-IdleNativeType
    $idleMilliseconds = [DisplayOffIdle.NativeMethods]::GetIdleMilliseconds()
    return [double]$idleMilliseconds / 1000.0
}

function Start-DisplayOffScript {
    Write-MonitorLog "Idle threshold reached ($IdleTimeoutSeconds seconds)."
    Write-MonitorLog "Calling display-off script: $DisplayOffScript"

    try {
        & $DisplayOffScript
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

        if ($exitCode -ne 0) {
            Write-MonitorLog "Display-off script exited with code $exitCode." 'ERROR'
        }
    }
    catch {
        Write-MonitorLog "Display-off script failed: $($_.Exception.Message)" 'ERROR'
    }
}

try {
    Initialize-Directories

    if (-not (Test-Path -LiteralPath $DisplayOffScript -PathType Leaf)) {
        Initialize-Directories
        Write-MonitorLog "Missing required script: $DisplayOffScript" 'ERROR'
        throw "Missing required script: $DisplayOffScript"
    }

    $hash = Get-StableNameHash -Text $PSScriptRoot
    $mutexName = "Local\$ProjectName-$hash"
    $mutex = [System.Threading.Mutex]::new($true, $mutexName, [ref]$ownsMutex)

    if (-not $ownsMutex) {
        Write-MonitorLog "Duplicate instance prevented."
        exit 0
    }

    Set-Content -LiteralPath $PidFile -Value $CurrentProcessId -Encoding ascii
    Write-MonitorLog "Monitor started. PID=$CurrentProcessId, idle timeout=$IdleTimeoutSeconds seconds, poll interval=$PollIntervalSeconds seconds."

    while ($true) {
        $idleSeconds = Get-IdleTimeSeconds

        if ($idleSeconds -ge $IdleTimeoutSeconds) {
            if (-not $DisplayTurnedOffForCurrentIdlePeriod) {
                Start-DisplayOffScript

                # GetLastInputInfo may keep reporting the same idle period after
                # monitor power-off. This flag prevents repeated calls until real
                # user input resets the idle timer.
                $DisplayTurnedOffForCurrentIdlePeriod = $true
            }
        }
        elseif ($DisplayTurnedOffForCurrentIdlePeriod) {
            Write-MonitorLog "User activity detected after display-off. Idle timer reset."
            $DisplayTurnedOffForCurrentIdlePeriod = $false
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
catch {
    Write-MonitorLog "Error occurred: $($_.Exception.Message)" 'ERROR'
    throw
}
finally {
    Write-MonitorLog "Monitor stopped."

    if (Test-Path -LiteralPath $PidFile) {
        $pidText = Get-Content -LiteralPath $PidFile -Raw -ErrorAction SilentlyContinue
        if ($pidText -and ($pidText.Trim() -eq [string]$CurrentProcessId)) {
            Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        }
    }

    if ($ownsMutex -and $null -ne $mutex) {
        $mutex.ReleaseMutex()
    }

    if ($null -ne $mutex) {
        $mutex.Dispose()
    }
}
