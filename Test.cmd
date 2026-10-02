@echo off
powershell -NoProfile -ExecutionPolicy ByPass -File "%~dp0eng\common\build.ps1" -test %*
exit /b %ErrorLevel%
