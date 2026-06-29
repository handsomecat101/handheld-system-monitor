@echo off
setlocal
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator permission for TDP and hardware controls...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~dp0SystemMonitor.exe' -Verb RunAs"
    exit /b
)

start "" "%~dp0SystemMonitor.exe"
