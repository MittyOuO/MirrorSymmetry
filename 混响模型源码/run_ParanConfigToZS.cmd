@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%run_ParanConfigToZS.ps1"
exit /b %ERRORLEVEL%
