@echo off
rem Double-click to install cvat-helpers.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" install
echo.
pause
