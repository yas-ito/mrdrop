@echo off
rem ---------------------------------------------------------------
rem  Mr.Drop - run once, without installing anything.
rem
rem  A black window opens and Mr.Drop runs while it stays open.
rem  Close the window and it stops. Nothing is left behind.
rem
rem  Most people should use the start file one folder up instead:
rem  it sets things up once, and no window stays open.
rem
rem  NOTE (for maintainers): ASCII only, CRLF.
rem ---------------------------------------------------------------
setlocal
cd /d "%~dp0.."

set "NODE=%~dp0..\node\node.exe"
if exist "%NODE%" goto run
where node >/dev/null 2>nul
if errorlevel 1 goto no_node
set "NODE=node"

:run
if not exist "%~dp0..\server\mrdrop.js" goto no_server
"%NODE%" "%~dp0..\server\mrdrop.js" %*
echo.
echo ---------------------------------------------------------------
echo  Mr.Drop stopped. You can close this window.
echo ---------------------------------------------------------------
pause
exit /b 0

:no_server
echo [ERROR] server\mrdrop.js was not found.
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
