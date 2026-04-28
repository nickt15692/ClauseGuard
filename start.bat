@echo off
setlocal EnableDelayedExpansion
title ClauseGuard

set "PROJECT_DIR=%~dp0"
cd /d "%PROJECT_DIR%"

echo.
echo  ----------------------------------------
echo    ClauseGuard - Starting up...
echo  ----------------------------------------
echo.

:: Check for .env
if not exist "%PROJECT_DIR%.env" (
    echo ERROR: .env file not found.
    echo Create it by running this in a terminal:
    echo   echo ANTHROPIC_API_KEY=your_key_here > .env
    echo.
    pause
    exit /b 1
)

:: Check for Python
where python >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not on PATH.
    echo Install it from https://www.python.org — check "Add to PATH" during install.
    echo.
    pause
    exit /b 1
)

:: Check for Node
where node >nul 2>&1
if errorlevel 1 (
    echo ERROR: Node.js is not installed or not on PATH.
    echo Install it from https://nodejs.org
    echo.
    pause
    exit /b 1
)

:: Set up Python venv (check for python.exe, not just the folder — folder can exist but be broken)
if not exist "%PROJECT_DIR%venv\Scripts\python.exe" (
    echo Creating Python virtual environment...
    python -m venv "%PROJECT_DIR%venv" --clear
    if errorlevel 1 (
        echo ERROR: Failed to create virtual environment.
        pause
        exit /b 1
    )
)

:: Upgrade pip to avoid wheel-finding issues on Windows
echo Upgrading pip...
"%PROJECT_DIR%venv\Scripts\python.exe" -m pip install --upgrade pip --quiet

:: Install Python dependencies
echo Installing Python dependencies...
"%PROJECT_DIR%venv\Scripts\pip.exe" install -r "%PROJECT_DIR%requirements.txt"
if errorlevel 1 (
    echo.
    echo ERROR: Failed to install Python dependencies.
    echo Check the output above for details.
    pause
    exit /b 1
)

:: Install Node dependencies
echo Installing Node dependencies...
cd /d "%PROJECT_DIR%frontend"
call npm install --silent
if errorlevel 1 (
    echo ERROR: Failed to install Node dependencies.
    pause
    exit /b 1
)
cd /d "%PROJECT_DIR%"

echo.
echo  ----------------------------------------
echo    Backend  ^>  http://localhost:8000
echo    Frontend ^>  http://localhost:3000
echo.
echo    Close this window to stop both servers.
echo  ----------------------------------------
echo.

:: Start backend in a new window (activate venv so uvicorn is on PATH)
start "ClauseGuard Backend" /d "%PROJECT_DIR%" cmd /k "call venv\Scripts\activate.bat && uvicorn backend.main:app --reload --port 8000"

:: Give backend a moment to start
timeout /t 2 /nobreak >nul

:: Start frontend in a new window (/d sets working dir, avoids nested-quote issues with spaces in path)
start "ClauseGuard Frontend" /d "%PROJECT_DIR%frontend" cmd /k "npm run dev"

echo Both servers are starting in separate windows.
echo.
echo You can close those windows to stop the servers.
echo.
pause
