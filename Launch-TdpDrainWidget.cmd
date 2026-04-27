@echo off
setlocal
set SCRIPT_DIR=%~dp0

if exist "%SCRIPT_DIR%dist-hotfix16\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix16\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix15\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix15\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix14\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix14\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix13\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix13\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix12\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix12\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix11\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix11\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix10\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix10\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix9\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix9\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix8\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix8\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix7\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix7\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix6\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix6\SystemMonitor.exe"
    exit /b
)

if exist "%SCRIPT_DIR%dist-hotfix5\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix5\SystemMonitor.exe"
    exit /b
)

if exist "%SCRIPT_DIR%dist-hotfix4\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix4\SystemMonitor.exe"
    exit /b
)

if exist "%SCRIPT_DIR%dist-hotfix3\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix3\SystemMonitor.exe"
    exit /b
)

if exist "%SCRIPT_DIR%dist-hotfix\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix\SystemMonitor.exe"
    exit /b
)

if exist "%SCRIPT_DIR%dist\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist\SystemMonitor.exe"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File "%SCRIPT_DIR%TdpDrainWidget.ps1"
