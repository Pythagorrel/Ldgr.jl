@echo off
REM Opens a Julia console with LDGR loaded, pointing at the real books. LDGR must be closed.
start "" /wait "%~dp0..\LDGR.exe" --console
