@echo off
powershell -NoProfile -ExecutionPolicy ByPass -File "%~dp0build.ps1" -restore -check -coverage -pack -ci %*
exit /b %ErrorLevel%
