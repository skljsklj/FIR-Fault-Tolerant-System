@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ================== Input ==================
if "%~1"=="" (
  set "TCL_SCRIPT=%~dp0create_project.tcl"
) else (
  set "TCL_SCRIPT=%~1"
)

if not exist "%TCL_SCRIPT%" (
  echo [ERROR] TCL script not found: "%TCL_SCRIPT%"
  exit /b 1
)

REM ================== If VIVADO_PATH preset ==================
if defined VIVADO_PATH (
  if exist "%VIVADO_PATH%" (
    echo [INFO] VIVADO_PATH found: "%VIVADO_PATH%"
    goto :RUN
  ) else (
    echo [WARN] VIVADO_PATH is set, but does not exist: "%VIVADO_PATH%"
  )
)

REM ================== Try PATH ==================
for /f "delims=" %%P in ('where vivado.bat 2^>nul') do (
  set "VIVADO_PATH=%%~fP"
  echo [INFO] vivado.bat found on PATH: "!VIVADO_PATH!"
  goto :RUN
)

REM ================== Try common roots one by one ==================
set "CANDIDATE="

call :TryRoot "C:\Xilinx"
if defined CANDIDATE goto :HAVE_CANDIDATE

call :TryRoot "D:\Xilinx"
if defined CANDIDATE goto :HAVE_CANDIDATE

call :TryRoot "%ProgramFiles%\Xilinx"
if defined CANDIDATE goto :HAVE_CANDIDATE

call :TryRoot "%ProgramFiles(x86)%\Xilinx"
if defined CANDIDATE goto :HAVE_CANDIDATE

echo [ERROR] Vivado not found. Set VIVADO_PATH or add Vivado to PATH.
echo         Checked: C:\Xilinx, D:\Xilinx, %%ProgramFiles%%\Xilinx, %%ProgramFiles(x86)%%\Xilinx
exit /b 2

:HAVE_CANDIDATE
set "VIVADO_PATH=%CANDIDATE%"
echo [INFO] Vivado found: "%VIVADO_PATH%"

:RUN
echo [INFO] Running: "%VIVADO_PATH%" -mode batch -source "%TCL_SCRIPT%"
"%VIVADO_PATH%" -mode batch -source "%TCL_SCRIPT%"
set ERR=%ERRORLEVEL%

if not "%ERR%"=="0" (
  echo [ERROR] Vivado finished with code: %ERR%
) else (
  echo [OK] Success!
)

pause
exit /b %ERR%

REM ================== Subroutines ==================
:TryRoot
REM %~1 = root like "C:\Xilinx" or "%ProgramFiles(x86)%\Xilinx"
if not exist %~1\Vivado goto :eof

REM /o-n -> sort by name descending; assumes folder names like 2024.1 > 2023.2
for /f "delims=" %%V in ('dir "%~1\Vivado" /b /ad /o-n 2^>nul') do (
  if exist "%~1\Vivado\%%V\bin\vivado.bat" (
    set "CANDIDATE=%~1\Vivado\%%V\bin\vivado.bat"
    goto :eof
  )
)
goto :eof