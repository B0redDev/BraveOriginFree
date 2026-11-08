@echo off
setlocal DisableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%
choice /C YN /M "Launch Brave Origin now"
if errorlevel 2 exit /b 0
wscript.exe //nologo "%~dp0Launch.vbs"
exit /b %ERRORLEVEL%
