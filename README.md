# System Monitor Widget

A Windows desktop widget built with PowerShell + WPF for monitoring:

- CPU power when the hardware backend exposes it
- battery drain / charging flow
- battery ETA
- internet online / offline state
- download / upload speed
- Wi-Fi / network name
- desktop internet loss notifications

## Features

- Clean floating widget UI
- Compact mode and full mode
- Tray icon with show/hide controls
- Startup with Windows toggle
- Desktop notification when internet is lost or restored
- Custom app icon for EXE, tray, and taskbar

## Project Layout

```text
.
|-- assets/
|   |-- SystemMonitor.ico
|   `-- SystemMonitor.png
|-- dist/
|-- scripts/
|   `-- Build-SystemMonitorExe.ps1
|-- Launch-TdpDrainWidget.cmd
|-- README.md
`-- TdpDrainWidget.ps1
```

## Run From Source

1. Open PowerShell.
2. Go to the repo folder.
3. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\TdpDrainWidget.ps1
```

Or just double-click:

```text
Launch-TdpDrainWidget.cmd
```

## Build EXE

This project uses `ps2exe`.

Run:

```powershell
.\scripts\Build-SystemMonitorExe.ps1
```

The built EXE is written to:

```text
dist\SystemMonitor.exe
```

## Notes

- CPU power depends on hardware sensor support. Some PCs expose it correctly, some do not.
- Battery data is only available on laptops / handhelds with a battery.
- The widget tries to find `LibreHardwareMonitorLib.dll` from common installed locations on the machine.
- `SystemMonitor.config.json` is generated locally and is intentionally ignored from git.

## Suggested GitHub Setup

- Commit the repo without `dist/` artifacts at first
- Add screenshots later if you want a nicer README
- Tag releases whenever you publish a new EXE build
