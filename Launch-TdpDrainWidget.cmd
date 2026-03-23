@echo off
setlocal
set SCRIPT_DIR=%~dp0

if exist "%SCRIPT_DIR%dist\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist\SystemMonitor.exe"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File "%SCRIPT_DIR%TdpDrainWidget.ps1"
