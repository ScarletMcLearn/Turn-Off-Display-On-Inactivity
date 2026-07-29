# Lists Windows power requests that can block display sleep.
# When blockers are gone and idle time reaches the threshold, counts down and turns off display.

[CmdletBinding()]
param(
    [int]$IdleMinutes = 1,
    [int]$PollSeconds = 5,
    [int]$CountdownSeconds = 10,
    [switch]$Once,
    [switch]$NoTurnOff
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    [Console]::Error.WriteLine('Run this script from an elevated PowerShell window: right-click PowerShell, choose "Run as administrator", then run this script again.')
    exit 1
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class DisplayOffNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll")]
    public static extern uint GetTickCount();

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
}
'@

function Get-IdleSeconds {
    $info = New-Object DisplayOffNative+LASTINPUTINFO
    $info.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($info)

    if (-not [DisplayOffNative]::GetLastInputInfo([ref]$info)) {
        throw 'GetLastInputInfo failed.'
    }

    $elapsedMs = [DisplayOffNative]::GetTickCount() - $info.dwTime
    return [math]::Floor($elapsedMs / 1000)
}

function Get-PowerRequests {
    $lines = & powercfg /requests 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg /requests failed: $($lines -join ' ')"
    }

    $category = $null
    $requests = New-Object System.Collections.Generic.List[object]

    foreach ($line in $lines) {
        $trimmed = $line.ToString().Trim()
        if ($trimmed -match '^(DISPLAY|SYSTEM|AWAYMODE|EXECUTION|PERFBOOST|ACTIVELOCKSCREEN):$') {
            $category = $matches[1]
            continue
        }

        if (-not $category -or $trimmed.Length -eq 0 -or $trimmed -eq 'None.') {
            continue
        }

        if ($trimmed -match '^\[(?<Type>[^\]]+)\]\s+(?<Name>.+)$') {
            $type = $matches.Type
            $name = $matches.Name
            $path = $null
            $processName = $null
            $pids = @()

            if ($type -eq 'PROCESS') {
                $path = $name
                $leaf = Split-Path -Leaf $path
                if ($leaf) {
                    $processName = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
                    $pids = @(Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
                }
            }

            $requests.Add([pscustomobject]@{
                Category = $category
                Type = $type
                Name = $name
                ProcessName = $processName
                Pids = $pids
            })
        }
    }

    return $requests
}

function Show-PowerRequests {
    param([object[]]$Requests)

    if ($Requests.Count -eq 0) {
        Write-Host 'No active power requests found.'
        return
    }

    $Requests |
        Sort-Object Category, Type, Name |
        Select-Object Category, Type, Name, ProcessName, @{Name='PIDs'; Expression={($_.Pids -join ', ')}} |
        Format-Table -AutoSize
}

function Turn-DisplayOff {
    $hwndBroadcast = [IntPtr]0xffff
    $wmSysCommand = 0x0112
    $scMonitorPower = [IntPtr]0xF170
    $monitorOff = [IntPtr]2

    [void][DisplayOffNative]::SendMessage($hwndBroadcast, $wmSysCommand, $scMonitorPower, $monitorOff)
}

$idleTargetSeconds = [math]::Max(1, $IdleMinutes * 60)

Write-Host "Display blocker monitor started. Idle target: $IdleMinutes minute(s)."
Write-Host 'End listed processes yourself; script will detect when blockers are gone.'

while ($true) {
    $requests = @(Get-PowerRequests)
    $processRequests = @($requests | Where-Object Type -eq 'PROCESS')

    Write-Host ''
    Write-Host "Checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Show-PowerRequests -Requests $requests

    if ($processRequests.Count -gt 0) {
        Write-Host ''
        Write-Host 'Processes currently blocking display sleep:'
        $processRequests |
            Sort-Object ProcessName, Name |
            Select-Object ProcessName, @{Name='PIDs'; Expression={($_.Pids -join ', ')}}, Name |
            Format-Table -AutoSize
    }

    if ($Once) {
        break
    }

    if ($requests.Count -eq 0) {
        $idleSeconds = Get-IdleSeconds
        $remainingIdle = $idleTargetSeconds - $idleSeconds

        if ($remainingIdle -gt 0) {
            Write-Host "No blockers. Waiting $remainingIdle more second(s) of inactivity."
            Start-Sleep -Seconds ([math]::Min($PollSeconds, $remainingIdle))
            continue
        }

        for ($seconds = $CountdownSeconds; $seconds -gt 0; $seconds--) {
            $newRequests = @(Get-PowerRequests)
            if ($newRequests.Count -gt 0) {
                Write-Host 'New blocker detected. Countdown cancelled.'
                Show-PowerRequests -Requests $newRequests
                Start-Sleep -Seconds $PollSeconds
                continue 2
            }

            if ((Get-IdleSeconds) -lt $idleTargetSeconds) {
                Write-Host 'Input detected. Countdown cancelled.'
                Start-Sleep -Seconds $PollSeconds
                continue 2
            }

            Write-Host "Turning display off in $seconds second(s). Press Ctrl+C to stop."
            Start-Sleep -Seconds 1
        }

        if ($NoTurnOff) {
            Write-Host 'NoTurnOff set. Display-off command skipped.'
        }
        else {
            Write-Host 'Turning display off now.'
            Turn-DisplayOff
        }

        break
    }

    Start-Sleep -Seconds $PollSeconds
}
