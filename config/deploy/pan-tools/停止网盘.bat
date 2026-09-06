@echo off
title Stop Netdisk
net session >nul 2>&1 || (powershell -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)
net stop __FB__ >nul 2>&1
net stop __FRP__ >nul 2>&1
echo Netdisk stopped.
pause
