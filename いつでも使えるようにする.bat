@echo off
rem ---------------------------------------------------------------
rem  Mr.Drop - keep it running in the background, with no window.
rem
rem  Double-click this file once. After that Mr.Drop starts by
rem  itself every time you log on, and no black window appears.
rem  Windows will ask for permission (that is for the firewall).
rem
rem  NOTE (for maintainers): ASCII only, CRLF.
rem ---------------------------------------------------------------
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\settings-windows.ps1" -MakeResident
pause
