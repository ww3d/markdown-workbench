@echo off
powershell -NoProfile -ExecutionPolicy ByPass -File "%~dp0eng\common\build.ps1" -restore -build %*
exit /b %ErrorLevel%
