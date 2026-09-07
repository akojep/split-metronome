@echo off
title Split Metronome server
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
echo.
echo Server stopped.
pause
