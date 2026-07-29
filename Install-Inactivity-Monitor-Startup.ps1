#Requires -Version 5.1
<#
Creates a current-user Scheduled Task that starts the inactivity monitor at
sign-in. It does not change Windows security, sign-in, screen saver, Dynamic
Lock, presence sensing, sleep, password, or power settings.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'DisplayOffInactivityMonitor'
$StartScript = Join-Path -Path $PSScriptRoot -ChildPath 'Start-Inactivity-Monitor.cmd'

if (-not (Test-Path -LiteralPath $StartScript -PathType Leaf)) {
    throw "Missing required script: $StartScript"
}

$userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$StartScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel LeastPrivilege
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable:$false `
    -WakeToRun:$false `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Starts the display-off inactivity monitor for the current user.' `
    -Force | Out-Null

Write-Output "Installed Scheduled Task '$TaskName' for $userId."
