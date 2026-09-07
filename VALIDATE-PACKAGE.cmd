@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VALIDATE-PACKAGE.ps1"
exit /b %ERRORLEVEL%
