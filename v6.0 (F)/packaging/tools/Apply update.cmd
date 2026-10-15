@echo off
REM Installs an update: drag the update zip file onto this file. LDGR must be closed.
if "%~1"=="" (
  echo Drag the update zip file onto "Apply update.cmd" to install it.
  pause
  exit /b 1
)
start "" /wait "%~dp0..\LDGR.exe" --update "%~1"
