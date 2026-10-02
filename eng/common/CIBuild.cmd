@echo off
powershell -NoProfile -ExecutionPolicy ByPass -File "%~dp0build.ps1" -ci %*
exit /b %ErrorLevel%
