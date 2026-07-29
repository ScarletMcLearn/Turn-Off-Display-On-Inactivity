# Turn Off Display

Windows 11 utilities that turn off connected displays without locking the PC, sleeping, hibernating, signing out, starting the screen saver, or stopping applications.

## Files

- `Turn-Off-Display.ps1` - one-shot PowerShell script that requests monitor power off through native Windows APIs.
- `Turn-Off-Display.cmd` - silent launcher for the one-shot display-off script.
- `Monitor-Inactivity.ps1` - continuous inactivity monitor. Default timeout: 60 seconds.
- `Start-Inactivity-Monitor.cmd` - starts the inactivity monitor hidden. Uses PowerShell 7 when available, otherwise Windows PowerShell.
- `Stop-Inactivity-Monitor.ps1` - stops only this project's inactivity monitor.
- `Install-Inactivity-Monitor-Startup.ps1` - optional current-user Scheduled Task installer.
- `Uninstall-Inactivity-Monitor-Startup.ps1` - removes only the Scheduled Task created by this project.
- `turn-off-inactive-screen.cmd` - small command wrapper for `on`, `off`, `now`, and `status`.

## How Display Off Works

`Turn-Off-Display.ps1` calls built-in `user32.dll` `SendMessage` with:

- `HWND_BROADCAST`
- `WM_SYSCOMMAND`
- `SC_MONITORPOWER`
- `lParam = 2`

`lParam = 2` requests monitor power off. Windows treats this as a display-power request, not a session lock or system power-state change.

The script does not call:

- `LockWorkStation`
- `SetSuspendState`
- shutdown, restart, sign-out, sleep, or hibernate commands
- screen saver commands
- fake keyboard input or fake mouse movement
- `powercfg` changes

After the request is sent, `Turn-Off-Display.ps1` exits. Normal user input, such as moving the mouse, clicking, or pressing a key, wakes the displays.

## How Inactivity Is Measured

`Monitor-Inactivity.ps1` uses `GetLastInputInfo` from `user32.dll`. Windows reports the tick count of the last real keyboard or mouse input. The script compares that value with the current Windows tick count and calculates idle seconds.

Tick-count rollover is handled with unsigned 32-bit subtraction, matching the native Windows `DWORD` timing model used by `GetLastInputInfo`.

The monitor polls once per second by default. It does not log polling cycles and does not busy loop.

State rule:

```text
If idle time is at least 60 seconds
    and display-off has not run in this idle period:
        call Turn-Off-Display.ps1
        mark display-off complete for this idle period

If real user input is detected:
    clear that mark
    start counting toward the next idle timeout
```

This means a five-minute idle period calls `Turn-Off-Display.ps1` once, not every second.

## Change Timeout

Edit near the top of `Monitor-Inactivity.ps1`:

```powershell
$IdleTimeoutSeconds = 60
```

Example:

```powershell
$IdleTimeoutSeconds = 300
```

That waits five minutes before turning displays off.

## Run One-Shot Display Off

From PowerShell 7:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Turn-Off-Display.ps1
```

From File Explorer:

```text
Double-click Turn-Off-Display.cmd
```

No administrator permission should be required for the display-off request.

## Start Monitor

From File Explorer:

```text
Double-click Start-Inactivity-Monitor.cmd
```

From PowerShell:

```powershell
.\Start-Inactivity-Monitor.cmd
```

The monitor starts hidden and keeps running in the background. It writes important events to:

```text
logs\InactivityMonitor.log
```

Small wrapper command from this folder:

```cmd
turn-off-inactive-screen on
turn-off-inactive-screen off
turn-off-inactive-screen now
turn-off-inactive-screen status
```

The same wrapper also accepts `-on`, `-off`, `-now`, and `-status`.

## Stop Monitor

From PowerShell:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Stop-Inactivity-Monitor.ps1
```

The stop script uses:

- `state\InactivityMonitor.pid`
- process command-line validation against this project's `Monitor-Inactivity.ps1`

It refuses to stop a PID that does not match this project, so unrelated PowerShell processes are not terminated.

## Duplicate Prevention

`Monitor-Inactivity.ps1` uses a named mutex based on this script folder. Starting it twice does not create two active monitors. A duplicate instance logs `Duplicate instance prevented` and exits.

`Start-Inactivity-Monitor.cmd` can be run repeatedly; the mutex still allows only one active monitor for this folder.

## Automatic Startup

Install current-user startup task:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-Inactivity-Monitor-Startup.ps1
```

Remove startup task:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Inactivity-Monitor-Startup.ps1
```

The Scheduled Task:

- runs only for the current user
- uses least privilege
- starts at user sign-in
- uses duplicate prevention
- does not wake the computer
- does not change sleep, lock-screen, screen-saver, password, sign-in, Dynamic Lock, presence-sensing, or power settings

## Execution Policy

The `.cmd` launchers use:

```text
-ExecutionPolicy Bypass
```

This applies only to that PowerShell process. It does not permanently change machine or user execution policy.

If direct `.ps1` execution is blocked, run with:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Monitor-Inactivity.ps1
```

## Confirm Apps Continue Running

Test long-running terminal work:

```powershell
ping 1.1.1.1 -t
```

Start the monitor, stop touching mouse/keyboard for more than 60 seconds, then wake displays with mouse or keyboard. Confirm `ping` continued.

Other expected behavior:

- Downloads continue.
- Browsers, terminals, scripts, automation tests, local servers, media apps, and network activity keep running.
- Audio usually continues unless Windows, an audio device, or the app pauses it independently.
- Multiple monitors should turn off together because `Turn-Off-Display.ps1` broadcasts the monitor-power command through Windows.

## Important Windows Settings

These scripts do not reduce security and do not permanently modify Windows settings.

Windows may still show the lock screen if existing settings or policy require sign-in after inactivity, absence, sleep, screen saver activation, Dynamic Lock, or presence sensing. Check manually if display wake shows the lock screen.

Check sign-in requirement:

1. Open `Settings`.
2. Go to `Accounts` > `Sign-in options`.
3. Check `If you've been away, when should Windows require you to sign in again?`.

Check screen saver password protection:

1. Open Start.
2. Search `Change screen saver`.
3. Check whether `On resume, display logon screen` is enabled.

Check Dynamic Lock:

1. Open `Settings`.
2. Go to `Accounts` > `Sign-in options`.
3. Check `Dynamic lock`.

Check presence sensing:

1. Open `Settings`.
2. Go to `Privacy & security` > `Presence sensing`.
3. Review presence-based lock or wake behavior, if supported by the device.

Check automatic sleep timers:

1. Open `Settings`.
2. Go to `System` > `Power & battery`.
3. Check `Screen and sleep`.

Do not change these settings unless you intentionally want different Windows security or power behavior.

## Troubleshooting

### Display Immediately Wakes

Common causes:

- Mouse, keyboard, touchpad, dock, KVM, USB hub, or monitor sends input noise.
- A desk bump moves the mouse.
- Wake-on-input device is too sensitive.
- Presence sensing wakes the display.
- Display driver or dock firmware wakes the display.

Try:

- Leave mouse untouched on a stable surface.
- Disconnect noisy input devices briefly.
- Test without dock, KVM, or USB hub.
- Check Windows presence sensing settings.
- Update GPU, dock, and monitor firmware if persistent.

### Wake Shows Lock Screen

These scripts do not lock Windows. Existing Windows settings or organization policy can still require sign-in after absence, sleep, screen saver, Dynamic Lock, or presence sensing. Review settings listed above.

### Only Some Monitors Turn Off

The Windows broadcast normally applies to the active display topology. If one display remains on:

- Confirm Windows detects all monitors in `Settings` > `System` > `Display`.
- Test with direct GPU connection instead of dock/KVM.
- Check monitor input/firmware behavior.
- Update GPU, dock, and monitor firmware.

### Monitor Will Not Start

Check:

- `Turn-Off-Display.ps1` exists in the same folder.
- PowerShell 7 `pwsh.exe` is installed, or Windows PowerShell `powershell.exe` is available.
- `logs\InactivityMonitor.log` has a clear error.

### Stop Script Refuses To Stop

This is intentional when the PID file points at a process that is not this project's monitor. It prevents killing unrelated PowerShell processes. Delete `state\InactivityMonitor.pid` only after confirming no monitor is running.

## Shortcut

Create desktop shortcut:

1. Right-click desktop.
2. Choose `New` > `Shortcut`.
3. Browse to `Turn-Off-Display.cmd` or `Start-Inactivity-Monitor.cmd`.
4. Name it.
5. Finish.

Assign keyboard shortcut:

1. Right-click the shortcut.
2. Choose `Properties`.
3. Select `Shortcut key`.
4. Press `Ctrl + Alt + M`.
5. Choose `OK`.

Pin:

- Start menu: right-click the shortcut and choose `Pin to Start` when available.
- Taskbar: right-click the shortcut and choose `Show more options` > `Pin to taskbar` when available.

Windows sometimes restricts pinning `.cmd` files directly. If so, create a shortcut first and pin that shortcut.
