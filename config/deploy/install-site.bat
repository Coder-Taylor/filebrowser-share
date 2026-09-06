@echo off
title Install My Netdisk
rem Launcher: request admin once, then run install-site.ps1 in THIS window (no extra popups).
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting admin rights - accept the UAC prompt...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
echo.
echo Running install-site.ps1 as administrator...
echo Follow the prompts (server addr / invite code / folder / password).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-site.ps1"
echo.
echo Install finished. exit=%errorlevel%
echo If you saw an error above, send this window to the owner.
pause
