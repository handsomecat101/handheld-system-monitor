# System Monitor Widget for GPD Win Mini

A lightweight Windows desktop widget for monitoring and quick handheld controls. The app is built with PowerShell + WPF and is tuned around the **GPD Win Mini Ryzen 7 7840U** workflow: small screen, quick TDP changes, fan mode buttons, battery/power awareness, and simple status cards while gaming.

![System Monitor Widget for GPD Win Mini](docs/images/gpd-win-mini-hero.png)

## Download

Recommended download for testers:

[Download SystemMonitor-hotfix38.zip](https://github.com/handsomecat101/handheld-system-monitor/raw/next/releases/SystemMonitor-hotfix38.zip)

Direct EXE only:

[Download SystemMonitor.exe](https://github.com/handsomecat101/handheld-system-monitor/raw/next/dist-hotfix38/SystemMonitor.exe)

Use the ZIP if you want the app to run correctly right away, because it includes the required `amd/` runtime files next to the EXE.

## What It Does

- Shows realtime CPU package power, CPU temperature, battery state, battery ETA, network status, and upload/download speed.
- Lets you switch TDP quickly with presets and a custom 4W-25W slider through bundled `ryzenadj`.
- Provides fan profile buttons: `Off`, `Low`, `Medium`, `Max`, `Auto`.
- Detects handheld gyro availability and exposes a simple `Off/On` switch in the UI.
- Includes compact/full view, pin toggle, display settings, and ENG/VIE language switch.
- Can be launched as a normal local Windows app without Motion Assistant.

## GPD Win Mini Focus

This project is intended as a practical replacement-style widget for GPD Win Mini users when the stock Motion Assistant workflow is not convenient or not working well.

Best-fit use cases:

- Quickly lower TDP for battery life.
- Raise TDP while plugged in for games.
- Watch battery drain and estimated runtime.
- Keep a compact system monitor open while using a handheld screen.
- Test fan/TDP behavior across games and firmware versions.

## Current Status

Latest local test build in this repo:

```text
dist-hotfix38\SystemMonitor.exe
```

Recommended launcher:

```text
Launch-TdpDrainWidget.cmd
```

The launcher automatically opens the newest available hotfix build, currently `dist-hotfix38`.

## Known Important Limitation

Fan control is still being validated on the real GPD Win Mini 7840U.

The app currently writes EC/PWM directly through the bundled `inpoutx64.dll`. On the test device, the UI can report that PWM was applied, but the fan may still stay at `0 rpm`. This means fan control should be treated as experimental until the EC register/mode handling is confirmed.

TDP control, monitor cards, UI layout, language switching, and gyro availability display are further along than fan control.

## Download / Run

For testers:

1. Download or clone this repo.
2. Open the project folder.
3. Double-click `Launch-TdpDrainWidget.cmd`.
4. If Windows blocks it, unblock the file or run it from PowerShell.
5. For TDP/fan features, running as Administrator may be required because the app uses low-level hardware access.

Run from source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\TdpDrainWidget.ps1
```

## Build EXE

Install `ps2exe` first if needed:

```powershell
Install-Module ps2exe -Scope CurrentUser
```

Build a new hotfix EXE:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-SystemMonitorExe.ps1 -OutputPath .\dist-hotfix39\SystemMonitor.exe -Version 1.0.39.0
```

Runtime dependencies used by the app live in `amd/`:

- `ryzenadj.exe`
- `inpoutx64.dll`
- `WinRing0x64.dll`
- `WinRing0x64.sys`

## Project Layout

```text
.
|-- amd/                         # low-level AMD/EC runtime binaries
|-- assets/                      # icon/image assets
|-- docs/                        # user guide and images
|-- dist-hotfix38/               # latest local test EXE build
|-- scripts/Build-SystemMonitorExe.ps1
|-- Launch-TdpDrainWidget.cmd
|-- README.md
`-- TdpDrainWidget.ps1           # main PowerShell/WPF app
```

## Tester Feedback Needed

When testing on a GPD Win Mini or another handheld, please report:

- Device model and CPU.
- BIOS/firmware version if known.
- Whether TDP changes apply correctly.
- Whether fan modes actually spin the fan and report RPM.
- Temperature behavior while gaming.
- Screenshot of the widget if the UI clips or overlaps.

## Documentation

- Vietnamese user guide: `docs/GUIDE_GPD_WIN_MINI_VI.md`
- Current handoff/state for future agents: `agent team/HANDOFF_CURRENT.md`
- GPD replacement roadmap: `agent team/ROADMAP_GPD_WIN_MINI_REPLACEMENT.md`

## Safety Notes

This app touches low-level performance and EC/fan controls. Use conservative settings first. If fan control behaves incorrectly, switch back to `Auto`, close the app, or reboot before heavy gaming.
