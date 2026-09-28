@echo off
setlocal

set "EA_DATABASE=%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-h1-ea-tester.sqlite"

call "%~dp0start-viewer.cmd" --ea-database "%EA_DATABASE%" --open-tab ea %*
exit /b %errorlevel%
