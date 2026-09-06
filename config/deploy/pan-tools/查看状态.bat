@echo off
title Netdisk status
sc query __FB__ | findstr STATE
sc query __FRP__ | findstr STATE
echo URL: __URL__
pause
