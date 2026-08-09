@echo off
setlocal
chcp 65001 >nul

set "PYTHONDONTWRITEBYTECODE=1"
set "PYTHON_EXE=%LOCALAPPDATA%\Python\bin\python.exe"

if not exist "%PYTHON_EXE%" (
    set "PYTHON_EXE=python.exe"
)

cd /d "%~dp0"

"%PYTHON_EXE%" -c "import sqlalchemy" >nul 2>&1
if errorlevel 1 (
    echo SQLAlchemy is not installed.
    echo Run the following command, then start the viewer again:
    echo "%PYTHON_EXE%" -m pip install -r "%~dp0requirements.txt"
    pause
    exit /b 1
)

"%PYTHON_EXE%" app.py --open-browser

if errorlevel 1 (
    echo.
    echo ZigZagElliot Alert Viewer could not be started.
    echo Confirm that Python is installed, then try again.
    pause
)

endlocal
