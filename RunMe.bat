@echo off
setlocal enabledelayedexpansion

rem ===================================================================
rem  Autopilot Hash Capture - launcher
rem  Works at OOBE (Shift+F10, already SYSTEM) and on a deployed device.
rem ===================================================================

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%Get-AutopilotHash.ps1"

if not exist "%PS1%" (
    echo ERROR: Get-AutopilotHash.ps1 not found next to this launcher.
    echo Expected: "%PS1%"
    pause
    exit /b 1
)

rem --- Pick the 64-bit PowerShell host.
rem --- Sysnative only exists when THIS process is 32-bit on a 64-bit OS,
rem --- so testing for it is a reliable way to reach the real System32.
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
    set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

if not exist "%PSEXE%" (
    echo ERROR: Could not locate powershell.exe.
    pause
    exit /b 1
)

rem --- Elevate if needed. At OOBE the Shift+F10 prompt is already SYSTEM,
rem --- so this passes through silently with no UAC prompt.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    if "%~1"=="" (
        "%PSEXE%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        "%PSEXE%" -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

rem --- Run from the script's own folder so relative output lands on the USB.
pushd "%SCRIPT_DIR%"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%errorlevel%"
popd

exit /b %RC%
