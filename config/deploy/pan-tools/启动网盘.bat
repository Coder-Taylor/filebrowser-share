@echo off
title Start Netdisk
net session >nul 2>&1 || (powershell -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)
net start __FB__ >nul 2>&1
net start __FRP__ >nul 2>&1
echo Netdisk started.  URL: __URL__
pause
