@echo off
powershell -NoProfile -ExecutionPolicy ByPass -File "%~dp0eng\common\build.ps1" -build %*
exit /b %ErrorLevel%
