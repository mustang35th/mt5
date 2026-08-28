@echo off
setlocal
chcp 65001 >nul

set "PYTHONDONTWRITEBYTECODE=1"
set "PYTHON_EXE=%LOCALAPPDATA%\Python\bin\python.exe"
set "VIEWER_URL=http://127.0.0.1:5187/"
set "VIEWER_HEALTH_URL=http://127.0.0.1:5187/api/health"

if not exist "%PYTHON_EXE%" (
    set "PYTHON_EXE=python.exe"
)

cd /d "%~dp0"

if not "%~1"=="" goto start_viewer

powershell.exe -NoProfile -NonInteractive -Command "$ErrorActionPreference = 'Stop'; $health = Invoke-RestMethod -Uri '%VIEWER_HEALTH_URL%' -TimeoutSec 3; if ($health.status -ne 'ok' -or [string]::IsNullOrWhiteSpace([string]$health.database)) { exit 1 }" >nul 2>&1
if not errorlevel 1 (
    echo ZigZagElliot Alert Viewer is already running.
    echo Opening %VIEWER_URL%
    start "" "%VIEWER_URL%"
    exit /b 0
)

:start_viewer

"%PYTHON_EXE%" -c "import sqlalchemy" >nul 2>&1
if errorlevel 1 (
    echo SQLAlchemy is not installed.
    echo Run the following command, then start the viewer again:
    echo "%PYTHON_EXE%" -m pip install -r "%~dp0requirements.txt"
    pause
    exit /b 1
)

"%PYTHON_EXE%" app.py --open-browser --allowed-host "steelers.tail9d1d2a.ts.net" --allowed-host "steelers.tail9d1d2a.ts.net:443" %*

if errorlevel 1 (
    echo.
    echo ZigZagElliot Alert Viewer could not be started.
    echo Review the error above, then confirm that Python and SQLAlchemy are installed.
    echo If port 5187 is occupied by another application, stop it or choose another port.
    pause
)

endlocal
