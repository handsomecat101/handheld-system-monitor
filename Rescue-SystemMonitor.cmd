@echo off
setlocal
set ROOT=%~dp0
set EXE=%ROOT%dist-hotfix15\SystemMonitor.exe
set CFG=%ROOT%dist-hotfix15\SystemMonitor.config.json

taskkill /F /IM SystemMonitor.exe /T >nul 2>nul
timeout /t 1 /nobreak >nul

(
echo {
echo   "Left": 120,
echo   "Top": 90,
echo   "IsPinned": true,
echo   "IsCompact": false,
echo   "ShowTdpCustomPanel": false,
echo   "TdpCustomW": 6,
echo   "ShowModesPanel": false,
echo   "FpsLimiter": 0,
echo   "EnableEdgeSidebar": false,
echo   "EdgeAutoHideSeconds": 4,
echo   "EnableInternetNotifications": true,
echo   "StartWithWindows": false
echo }
) > "%CFG%"

start "" "%EXE%"
exit /b
