@echo off
setlocal
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0REPO-BACKUP-STATUS.ps1"
exit /b %ERRORLEVEL%
