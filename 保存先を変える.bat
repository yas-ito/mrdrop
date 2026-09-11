@echo off
rem ---------------------------------------------------------------
rem  Mr.Drop - choose the folder where received files are saved.
rem
rem  Double-click this file. A folder picker opens. Pick any folder
rem  (your video editing assets folder is the best use of this).
rem
rem  NOTE (for maintainers): ASCII only, CRLF. cmd.exe reads .bat as
rem  CP932 on Japanese Windows, so Japanese text lives in the .ps1.
rem ---------------------------------------------------------------
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\settings-windows.ps1" -ChooseInbox
pause
