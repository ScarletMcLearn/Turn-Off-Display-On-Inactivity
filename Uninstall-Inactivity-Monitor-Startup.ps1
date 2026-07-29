#Requires -Version 5.1
<#
Removes only the Scheduled Task created by Install-Inactivity-Monitor-Startup.ps1.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'DisplayOffInactivityMonitor'
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($null -eq $task) {
    Write-Output "Scheduled Task '$TaskName' is not installed."
    exit 0
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Output "Removed Scheduled Task '$TaskName'."
