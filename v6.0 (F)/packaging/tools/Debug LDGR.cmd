@echo off
REM Opens LDGR with developer tools, and shows the log live in a console window.
start "" /wait "%~dp0..\LDGR.exe" --debug
