@echo off
powershell -NoProfile -ExecutionPolicy ByPass -File "%~dp0build.ps1" -restore -task All -ci %*
exit /b %ErrorLevel%
