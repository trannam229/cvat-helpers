@echo off
rem Double-click to uninstall cvat-helpers.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" uninstall
echo.
pause
