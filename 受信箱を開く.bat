@echo off
rem ---------------------------------------------------------------
rem  Mr.Drop - open the folder where received files land.
rem  NOTE (for maintainers): ASCII only, CRLF.
rem ---------------------------------------------------------------
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\settings-windows.ps1" -OpenInbox
