#Requires -Version 5.1
<#
Turns off connected displays without locking, sleeping, hibernating, signing out,
starting the screen saver, or stopping running applications.

Uses the native Windows monitor-power message:
  SendMessage(HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, 2)

The script exits immediately after Windows receives the request. Normal keyboard
or mouse input wakes the displays again.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-DisplayPowerNativeType {
    if ('DisplayPower.NativeMethods' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace DisplayPower
{
    public static class NativeMethods
    {
        public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);
        public const int WM_SYSCOMMAND = 0x0112;
        public static readonly IntPtr SC_MONITORPOWER = new IntPtr(0xF170);

        // SC_MONITORPOWER lParam values:
        // -1 = on, 1 = low power, 2 = off
        public static readonly IntPtr MONITOR_POWER_OFF = new IntPtr(2);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessage(
            IntPtr hWnd,
            int Msg,
            IntPtr wParam,
            IntPtr lParam
        );
    }
}
'@
}

function Invoke-TurnDisplayOff {
    Add-DisplayPowerNativeType

    # Broadcast the monitor-power system command to all top-level windows.
    # This requests display power off only. It is not LockWorkStation, sleep,
    # hibernate, shutdown, sign-out, or screen-saver activation.
    [void][DisplayPower.NativeMethods]::SendMessage(
        [DisplayPower.NativeMethods]::HWND_BROADCAST,
        [DisplayPower.NativeMethods]::WM_SYSCOMMAND,
        [DisplayPower.NativeMethods]::SC_MONITORPOWER,
        [DisplayPower.NativeMethods]::MONITOR_POWER_OFF
    )
}

try {
    Invoke-TurnDisplayOff
    exit 0
}
catch {
    $message = $_.Exception.Message
    [Console]::Error.WriteLine("Failed to request display power off: $message")
    exit 1
}
