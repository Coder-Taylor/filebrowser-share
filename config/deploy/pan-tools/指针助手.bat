@echo off
title Pointer tool
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting admin - accept UAC...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0÷∏’Î÷˙ ÷.ps1"
echo.
echo Pointer tool finished. If an error appeared above, send it to the owner.
pause