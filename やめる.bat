@echo off
rem ---------------------------------------------------------------
rem  Mr.Drop - remove it from this PC.
rem
rem  Double-click this file. It stops Mr.Drop, closes the firewall
rem  hole, removes the auto-start and deletes what was installed.
rem
rem  Files you already received are NOT deleted.
rem
rem  Windows will ask for permission - that is for the firewall.
rem
rem  NOTE (for maintainers): ASCII only, CRLF.
rem  cmd.exe reads .bat as CP932 on Japanese Windows, so non-ASCII
rem  text in this file would break. Japanese wording belongs in
rem  scriptssettings-windows.ps1 and the HTML manual, not here.
rem
rem  This file is deliberately NOT copied into %LOCALAPPDATA%MrDrop:
rem  cmd.exe keeps a running .bat open and re-reads it line by line,
rem  so a .bat that deletes its own folder breaks halfway. After
rem  install, the way in is Start Menu > Mr.Drop (shortcuts that
rem  call powershell directly).
rem ---------------------------------------------------------------
setlocal
cd /d "%~dp0"

if not exist "%~dp0scriptssettings-windows.ps1" goto no_scripts

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scriptssettings-windows.ps1" -Uninstall
pause
exit /b 0

:no_scripts
echo [ERROR] scriptssettings-windows.ps1 was not found.
echo         Extract the whole ZIP, keeping the folders together.
echo.
pause
exit /b 1
