@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0GetPixivRefreshToken.ps1"
set EXITCODE=%errorlevel%
if %EXITCODE% neq 0 pause
exit /b %EXITCODE%
