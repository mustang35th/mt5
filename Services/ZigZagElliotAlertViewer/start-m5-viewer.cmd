@echo off
setlocal

set "M5_DATABASE=%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-zigzag-elliot-m5-observation.sqlite"

call "%~dp0start-viewer.cmd" --m5-database "%M5_DATABASE%" --open-tab m5 --open-source-mode LIVE %*
exit /b %errorlevel%
