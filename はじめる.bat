@echo off
rem ---------------------------------------------------------------
rem  Mr.Drop - set this PC up to receive, once and for all.
rem
rem  Double-click this file. It copies Mr.Drop into this PC
rem  (%LOCALAPPDATA%MrDropapp), opens the firewall (private
rem  network only) and makes it start by itself every time you log
rem  on. No black window stays open. You only do this once.
rem
rem  After that this extracted folder can be thrown away - it does
rem  not matter where you extracted it. From then on the way in is
rem  Start Menu > Mr.Drop.
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
