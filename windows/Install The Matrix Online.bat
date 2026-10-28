@echo off
rem Double-click to install The Matrix Online. Asks for admin rights once (needed to add the server to the hosts file).
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -STA -File \"%~dp0Install-MXO.ps1\"'"
