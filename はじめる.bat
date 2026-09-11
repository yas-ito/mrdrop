@echo off
rem ---------------------------------------------------------------
rem  Mr.Drop - set this PC up to receive, once and for all.
rem
rem  Double-click this file. It opens the firewall (private network
rem  only) and makes Mr.Drop start by itself every time you log on.
rem  No black window stays open. You only do this once.
rem
rem  Windows will ask for permission - that is for the firewall.
rem
rem  Just want to run it this once, without installing anything?
rem  Use scripts\run-once.bat instead.
rem
rem  NOTE (for maintainers): ASCII only, CRLF.
rem  cmd.exe reads .bat as CP932 on Japanese Windows, so non-ASCII
rem  text in this file would break. Japanese wording belongs in
rem  scripts\settings-windows.ps1 and the HTML manual, not here.
rem ---------------------------------------------------------------
setlocal
cd /d "%~dp0"

if not exist "%~dp0server\mrdrop.js" goto no_server
if not exist "%~dp0scripts\settings-windows.ps1" goto no_scripts

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\settings-windows.ps1" -MakeResident
pause
exit /b 0

:no_server
echo [ERROR] server\mrdrop.js was not found next to this file.
echo         Extract the whole ZIP, keeping the folders together.
echo.
pause
exit /b 1

:no_scripts
echo [ERROR] scripts\settings-windows.ps1 was not found.
echo         Extract the whole ZIP, keeping the folders together.
echo.
pause
exit /b 1
