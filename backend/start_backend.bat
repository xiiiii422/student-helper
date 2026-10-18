@echo off
rem Double-click to start the local backend (see run.ps1 for details).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1
pause
