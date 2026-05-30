@echo off
setlocal
set SCRIPT_DIR=%~dp0

if exist "%SCRIPT_DIR%dist-hotfix38\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix38\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix37\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix37\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix36\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix36\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix35\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix35\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix34\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix34\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix33\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix33\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix32\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix32\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix31\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix31\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix30\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix30\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix29\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix29\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix28\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix28\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix27\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix27\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix26\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix26\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix25\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix25\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix24\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix24\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix23\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix23\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix22\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix22\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix21\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix21\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix20\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix20\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix19\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix19\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix18\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix18\SystemMonitor.exe"
    exit /b
)
if exist "%SCRIPT_DIR%dist-hotfix17\SystemMonitor.exe" (
    start "" "%SCRIPT_DIR%dist-hotfix17\SystemMonitor.exe"
    exit /b
)
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
