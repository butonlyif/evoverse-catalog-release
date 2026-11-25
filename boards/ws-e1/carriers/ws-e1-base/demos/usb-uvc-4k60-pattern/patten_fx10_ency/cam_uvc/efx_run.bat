@echo off
if not defined EFINITY_HOME (
	call %~dp0setup.bat
)

setlocal
set QT_PLUGIN_PATH=%EFINITY_HOME%/python311
@"%EFINITY_HOME%\python311\bin\python.exe" "%EFINITY_HOME%\scripts\efx_run.py" %*

if %ERRORLEVEL% NEQ 0 (
	exit /b %ERRORLEVEL%
)

endlocal
