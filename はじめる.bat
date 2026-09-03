@echo off
rem ---------------------------------------------------------------
rem  Mr.Drop - start the receiver on this PC.
rem
rem  Just double-click this file, then open the shown address on
rem  your iPhone. Keep this window open while you send files.
rem
rem  NOTE (for maintainers): ASCII only, CRLF.
rem  cmd.exe reads .bat as CP932 on Japanese Windows, so non-ASCII
rem  text in this file would break. Japanese wording belongs in
rem  the HTML manual, not here.
rem ---------------------------------------------------------------
setlocal
cd /d "%~dp0"

rem 1) node.exe shipped next to this file (the packaged version).
set "NODE=%~dp0node\node.exe"
if exist "%NODE%" goto run

rem 2) Source checkout: use the Node.js installed on this PC.
where node >nul 2>nul
if errorlevel 1 goto no_node
set "NODE=node"

:run
if not exist "%~dp0server\mrdrop.js" goto no_server
"%NODE%" "%~dp0server\mrdrop.js" %*
echo.
echo ---------------------------------------------------------------
echo  Mr.Drop stopped. You can close this window.
echo ---------------------------------------------------------------
pause
exit /b 0

:no_server
echo [ERROR] server\mrdrop.js was not found next to this file.
echo         Extract the whole ZIP, keeping the folders together.
echo.
pause
exit /b 1

:no_node
echo [ERROR] Node.js was not found, and no bundled node\node.exe.
echo         Get Node.js (LTS) from https://nodejs.org/ja
echo.
pause
exit /b 1
